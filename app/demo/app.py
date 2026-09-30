import json
import os
import re
import sys
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_NAME = os.getenv("SERVICE_NAME", "product")
PORT = int(os.getenv("PORT", "8080"))
DB_HOST = os.getenv("DB_HOST", "")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "appdb")
DB_USER = os.getenv("DB_USER") or os.getenv("DB_USERNAME", "appadmin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_SSLMODE = os.getenv("DB_SSLMODE", "require")
AWS_REGION = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "unknown"))

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""

# Detect available postgres driver
try:
    import psycopg2
    import psycopg2.extras

    DB_DRIVER = "psycopg2"
except ImportError:
    try:
        import psycopg

        DB_DRIVER = "psycopg3"
    except ImportError:
        DB_DRIVER = None

_schema_initialized = False


def log_event(level, message, operation=None, **kwargs):
    entry = {
        "level": level,
        "service": SERVICE_NAME,
        "region": AWS_REGION,
        "db_host": DB_HOST if DB_HOST else "not-configured",
        "message": message,
    }
    if operation:
        entry["operation"] = operation
    for k, v in kwargs.items():
        if "password" in k.lower() or "secret" in k.lower():
            continue
        entry[k] = v
    print(json.dumps(entry), flush=True)


def get_db_connection():
    if not DB_HOST:
        raise ValueError("DB_HOST is not configured")
    if DB_DRIVER == "psycopg2":
        return psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            sslmode=DB_SSLMODE,
            connect_timeout=3,
        )
    elif DB_DRIVER == "psycopg3":
        return psycopg.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            sslmode=DB_SSLMODE,
            connect_timeout=3,
            autocommit=True,
        )
    else:
        raise RuntimeError("No PostgreSQL driver (psycopg2 or psycopg) is installed")


def ensure_schema():
    global _schema_initialized
    if _schema_initialized or not DB_HOST:
        return
    try:
        conn = get_db_connection()
        try:
            with conn.cursor() as cur:
                cur.execute(SCHEMA_SQL)
            if hasattr(conn, "commit"):
                conn.commit()
            _schema_initialized = True
            log_event("info", "Database schema initialized/verified", operation="schema_init")
        finally:
            conn.close()
    except Exception as e:
        log_event(
            "error",
            f"Database schema initialization failed: {str(e)}",
            operation="schema_init",
        )
        raise


def check_db_health():
    if not DB_HOST:
        return True, "not-configured", None
    try:
        ensure_schema()
        conn = get_db_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
            return True, "connected", None
        finally:
            conn.close()
    except Exception as e:
        err_msg = str(e)
        log_event(
            "error",
            f"Database health check failed: {err_msg}",
            operation="health_check",
        )
        return False, "disconnected", err_msg


def list_products():
    ensure_schema()
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, price, created_at FROM products ORDER BY id ASC;")
            rows = cur.fetchall()
            products = []
            for row in rows:
                if isinstance(row, dict):
                    products.append({
                        "id": row["id"],
                        "name": row["name"],
                        "price": float(row["price"]),
                        "created_at": row["created_at"].isoformat() if row.get("created_at") else None,
                    })
                else:
                    products.append({
                        "id": row[0],
                        "name": row[1],
                        "price": float(row[2]),
                        "created_at": row[3].isoformat() if row[3] else None,
                    })
            return products
    finally:
        conn.close()


def create_product(name, price):
    ensure_schema()
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO products (name, price) VALUES (%s, %s) RETURNING id, name, price, created_at;",
                (name, price),
            )
            row = cur.fetchone()
        if hasattr(conn, "commit"):
            conn.commit()
        if isinstance(row, dict):
            return {
                "id": row["id"],
                "name": row["name"],
                "price": float(row["price"]),
                "created_at": row["created_at"].isoformat() if row.get("created_at") else None,
            }
        else:
            return {
                "id": row[0],
                "name": row[1],
                "price": float(row[2]),
                "created_at": row[3].isoformat() if row[3] else None,
            }
    finally:
        conn.close()


def get_product(product_id):
    ensure_schema()
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, price, created_at FROM products WHERE id = %s;",
                (product_id,),
            )
            row = cur.fetchone()
        if not row:
            return None
        if isinstance(row, dict):
            return {
                "id": row["id"],
                "name": row["name"],
                "price": float(row["price"]),
                "created_at": row["created_at"].isoformat() if row.get("created_at") else None,
            }
        else:
            return {
                "id": row[0],
                "name": row[1],
                "price": float(row[2]),
                "created_at": row[3].isoformat() if row[3] else None,
            }
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, body):
        payload = json.dumps(body, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format_string, *args):
        log_event("info", format_string % args, operation="http_access")

    def _normalize_path(self):
        path = self.path.split("?")[0].rstrip("/")
        if not path:
            path = "/"
        return path

    def do_GET(self):
        path = self._normalize_path()

        # Health check endpoints: /health, /{service}/health, /product/health, /products/health
        if path == "/health" or path.endswith("/health"):
            ready, db_status, _ = check_db_health()
            status_code = 200 if ready else 503
            self._reply(
                status_code,
                {
                    "status": "healthy" if ready else "unhealthy",
                    "service": SERVICE_NAME,
                    "database": db_status,
                    "region": AWS_REGION,
                },
            )
            return

        # List all products: /products, /product, /{service}/products, /{service}/product
        if path in (
            "/products",
            "/product",
            f"/{SERVICE_NAME}/products",
            f"/{SERVICE_NAME}/product",
        ):
            try:
                products = list_products()
                self._reply(200, products)
            except Exception as e:
                log_event("error", f"Failed to list products: {str(e)}", operation="list_products")
                self._reply(500, {"error": "Failed to query database", "detail": str(e)})
            return

        # Single product by ID: /products/{id}, /product/{id}, /{service}/products/{id}, /{service}/product/{id}
        match = re.match(r"^(?:/[a-zA-Z0-9_-]+)?/products?/(\d+)$", path)
        if match:
            product_id = int(match.group(1))
            try:
                product = get_product(product_id)
                if product:
                    self._reply(200, product)
                else:
                    self._reply(404, {"error": f"Product with id {product_id} not found"})
            except Exception as e:
                log_event("error", f"Failed to get product {product_id}: {str(e)}", operation="get_product")
                self._reply(500, {"error": "Failed to query database", "detail": str(e)})
            return

        # Service-specific discovery endpoints: /auth, /order
        for svc in ("auth", "order"):
            if path == f"/{svc}" or path.startswith(f"/{svc}/"):
                self._reply(200, {"service": svc, "region": AWS_REGION, "status": "active"})
                return

        # Service endpoint matching current service name
        if path == f"/{SERVICE_NAME}" or path.startswith(f"/{SERVICE_NAME}/"):
            self._reply(200, {"service": SERVICE_NAME, "region": AWS_REGION, "status": "active"})
            return

        self._reply(404, {"error": "not found", "path": path})

    def do_POST(self):
        path = self._normalize_path()

        # Create product: /products, /product, /{service}/products, /{service}/product
        if path in (
            "/products",
            "/product",
            f"/{SERVICE_NAME}/products",
            f"/{SERVICE_NAME}/product",
        ):
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length <= 0:
                self._reply(400, {"error": "Request body cannot be empty"})
                return

            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
            except Exception:
                self._reply(400, {"error": "Invalid JSON body"})
                return

            name = data.get("name")
            price = data.get("price")

            if not name or not isinstance(name, str) or not name.strip():
                self._reply(400, {"error": "'name' is required and must be a non-empty string"})
                return

            try:
                price = float(price)
                if price < 0:
                    raise ValueError("Price must be positive")
            except (TypeError, ValueError):
                self._reply(400, {"error": "'price' is required and must be a valid non-negative number"})
                return

            try:
                created = create_product(name.strip(), price)
                log_event("info", f"Created product {created['id']}: {created['name']}", operation="create_product")
                self._reply(201, created)
            except Exception as e:
                log_event("error", f"Failed to create product: {str(e)}", operation="create_product")
                self._reply(500, {"error": "Failed to insert into database", "detail": str(e)})
            return

        self._reply(404, {"error": "not found", "path": path})


if __name__ == "__main__":
    log_event(
        "info",
        f"Starting {SERVICE_NAME} microservice on port {PORT}",
        operation="startup",
    )
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
