# NT533 — Low-Cost Multi-Region Backup & Restore DR trên AWS

Project này triển khai một environment duy nhất: **production**. Workload chính chạy tại Sydney (`ap-southeast-2`); Singapore (`ap-southeast-1`) chỉ giữ backup, image và control plane DR. VPC, NAT Gateway, ALB, ECS services và RDS tại Singapore chỉ được tạo sau khi sự cố primary được xác nhận.

> Trạng thái bàn giao: code và kiểm tra tĩnh local. Chưa deploy AWS, chưa tạo recovery point, chưa chạy DR test, vì phiên làm việc hiện tại không có AWS credentials. Không xem các bước kiểm tra file là bằng chứng RTO/RPO thực tế.

## 1. Kiến trúc và quyết định chính

```text
Normal
Users -> Route 53 PRIMARY -> Sydney ALB -> ECS Fargate -> RDS PostgreSQL
                                                       -> AWS Backup
                                                          -> cross-Region recovery point (Singapore)
Sydney ECR -> cross-Region replication -> Singapore ECR

Confirmed disaster
CloudWatch alarm (Sydney)
  -> EventBridge cross-Region bus (Singapore)
  -> Step Functions
  -> wait 90s + recheck alarm
  -> CloudFormation CreateStack (VPC/NAT/ALB/ECS desired=0)
  -> latest Singapore recovery point
  -> AWS Backup restore RDS
  -> copy replicated credentials + restored endpoint into DR runtime secret
  -> ECS desired count 0 -> production count
  -> all three target groups healthy
  -> recheck primary immediately before cutover
  -> create Route 53 SECONDARY failover alias
  -> SNS
```

Đây là **Backup & Restore**, không phải Pilot Light, Warm Standby hay Active/Active:

- Ưu điểm: standby cost thấp nhất; bình thường không trả phí DR RDS, ALB, NAT hay Fargate tasks.
- Đổi lại: RTO dài vì phải dựng network/ALB/ECS rồi restore RDS. Với RDS lớn, restore thường là phần chi phối.
- Backup mỗi 6 giờ giảm chi phí/tần suất so với hourly nhưng theoretical RPO có thể gần 6 giờ, cộng độ trễ copy. Đây không phải cam kết; phải đo timestamp recovery point thực tế.

CloudFormation chịu trách nhiệm **desired infrastructure**. Step Functions chịu trách nhiệm **quy trình động** và các gate an toàn. Secondary DNS không tồn tại trước disaster và chỉ được UPSERT sau khi data → application → health đều sẵn sàng.

## 2. Repository tree

```text
app/demo/                              # container HTTP nhỏ dùng chung cho 3 service
cloudformation/
├── bootstrap/
│   ├── regional-baseline.yaml         # artifact bucket + regional backup vault
│   └── dr-ecr.yaml                    # secure destination repositories, no compute
├── primary/
│   ├── root-primary.yaml
│   ├── network.yaml
│   ├── security.yaml
│   ├── alb.yaml
│   ├── ecs.yaml
│   ├── rds.yaml
│   ├── ecr.yaml
│   ├── backup.yaml
│   ├── route53.yaml
│   └── monitoring.yaml
├── dr/
│   ├── root-dr.yaml                   # chỉ CreateStack khi DR
│   ├── network.yaml
│   ├── security.yaml
│   ├── alb.yaml
│   ├── iam.yaml
│   ├── ecs.yaml                       # desired count ban đầu = 0
│   └── monitoring.yaml
├── automation/
│   ├── root-automation.yaml
│   ├── iam.yaml
│   ├── sns.yaml
│   ├── lock.yaml                      # DynamoDB singleton lock with TTL
│   ├── lambda.yaml
│   ├── stepfunctions.yaml
│   ├── eventbridge-dr.yaml
│   ├── eventbridge-primary.yaml
│   └── lambda/<single-purpose>/index.py # 7 small Lambdas
├── parameters/
│   ├── prod-primary.json
│   ├── prod-dr.json
│   └── prod-automation.json
└── scripts/
    ├── validate.ps1
    ├── package.ps1
    ├── publish-images.ps1
    ├── invoke-dr-test.ps1
    └── cleanup-dr-test.ps1            # destructive; explicit guard required
```

## 3. Current-service checks

Kiến trúc đã đối chiếu tài liệu hiện hành ngày 2026-09-16:

- Step Functions có endpoint tại cả Sydney và Singapore và AWS SDK integration hỗ trợ AWS Backup, CloudFormation, ECS, RDS, Route 53 và các API liên quan.
- EventBridge hỗ trợ target là event bus ở Region khác; vì alarm phát sinh tại Sydney còn state machine nằm tại Singapore, project dùng Sydney rule → Singapore custom bus → state machine.
- `AWS::ECR::ReplicationConfiguration` là resource CloudFormation hiện hành. Chỉ image push **sau** khi bật replication mới tự replicate; image cũ phải push lại.
- AWS Backup restore dùng `GetRecoveryPointRestoreMetadata` + `StartRestoreJob`; Lambda `start-restore` chỉ hợp nhất metadata network/identifier cần thiết.

Nguồn chính: [Step Functions endpoints](https://docs.aws.amazon.com/general/latest/gr/step-functions.html), [AWS SDK integrations](https://docs.aws.amazon.com/step-functions/latest/dg/supported-services-awssdk.html), [EventBridge cross-Region](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-region.html), [ECR replication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html), [AWS Backup RDS restore](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-rds.html).

## 4. Security model

- RDS nằm trong isolated DB subnets, `PubliclyAccessible=false`, storage KMS-encrypted, PostgreSQL `rds.force_ssl=1`.
- ECS chỉ nhận port 8080 từ ALB SG; RDS chỉ nhận port 5432 từ ECS SG.
- Credential được Secrets Manager sinh, không nằm trong template/Git. Secret primary được replicate sang Singapore. Khi restore, Lambda chỉ đọc replica và tạo runtime secret riêng chứa endpoint DR.
- Artifact buckets block toàn bộ public access, bật versioning/encryption và deny non-TLS.
- SNS dùng customer-managed KMS key có rotation; key policy cho phép SNS/EventBridge/Step Functions dùng key trong đúng account và encryption context của topic. CloudWatch/Step Functions logs có retention.
- EventBridge targets có retry 24 giờ và encrypted SQS DLQ giữ event lỗi 14 ngày.
- DynamoDB conditional write tạo singleton lock: chỉ một DR execution được phép dựng stack/restore/cutover; TTL giải phóng lock bị orphan sau timeout.
- Không role nào dùng `AdministratorAccess`. Một số create/list/describe API bắt buộc `Resource: '*'` vì resource chưa tồn tại hoặc API không hỗ trợ resource-level permission; các action vẫn được liệt kê cụ thể. Step Functions chỉ `PassRole` CloudFormation execution role cho `cloudformation.amazonaws.com`; role đó chỉ `PassRole` các runtime task roles có prefix của DR stack cho `ecs-tasks.amazonaws.com`.

Demo `/health` dùng TCP probe có timeout tới RDS để ALB không đánh dấu target healthy khi database endpoint chưa reachable. Đây là infrastructure readiness gate, không thay thế transaction/canary kiểm tra tính đúng dữ liệu; workload production phải bổ sung query/read-write canary phù hợp schema.

Trong production thật nên thêm permission boundary/SCP, CloudTrail organization trail, AWS Config, WAF trên ALB, ALB access logs và customer-managed KMS key cho log groups nếu policy tổ chức yêu cầu.

## 5. Prerequisites

- AWS CLI v2 và một session ngắn hạn qua IAM Identity Center/assume-role; không dùng access key commit vào repo.
- Docker Desktop cho demo image.
- `uv` để chạy `cfn-lint` qua `uvx`.
- Public Route 53 hosted zone và domain/subdomain.
- ACM certificate tại **từng Region** nếu bật HTTPS. Certificate của Sydney không dùng được cho ALB Singapore.
- Quyền deploy CloudFormation/IAM, upload S3, ECR push, Backup, Route 53, EventBridge và Step Functions.

Thay toàn bộ `REPLACE_WITH_*` trong `cloudformation/parameters/*.json`. Giữ CIDR `10.10.0.0/16` và `10.20.0.0/16` không overlap.

## 6. Validation trước deploy

```powershell
pwsh -File .\cloudformation\scripts\validate.ps1
```

Project bắt buộc đi qua `aws cloudformation package`: local nested `TemplateURL` và Lambda `Code` không phải template deploy trực tiếp. Warning `W3002` vì lý do này là expected. Trong phiên xây dựng, `cfn-lint 1.56.3` đã chạy cho cả `ap-southeast-2` và `ap-southeast-1` và không còn schema error; ASL JSON parse thành công với 57 states. Chưa chạy `cfn-guard` vì máy chưa có binary/ruleset, và chưa chạy `validate-state-machine-definition` vì AWS CLI chưa có credentials.

## 7. Deployment order

Mọi stack production phải qua change set. Không execute nếu change set có delete/replace ngoài dự kiến.

### Phase 0 — regional baseline

Lấy account ID qua `aws sts get-caller-identity`, sau đó deploy baseline ở mỗi Region. Bucket name phải globally unique.

```powershell
$accountId = aws sts get-caller-identity --query Account --output text

aws cloudformation deploy --stack-name prod-dr-primary-baseline `
  --template-file .\cloudformation\bootstrap\regional-baseline.yaml `
  --region ap-southeast-2 `
  --parameter-overrides ProjectName=prod-dr ArtifactBucketName="prod-dr-cfn-artifacts-$accountId-ap-southeast-2" BackupVaultName=prod-primary-backup-vault `
  --no-execute-changeset

aws cloudformation deploy --stack-name prod-dr-dr-baseline `
  --template-file .\cloudformation\bootstrap\regional-baseline.yaml `
  --region ap-southeast-1 `
  --parameter-overrides ProjectName=prod-dr ArtifactBucketName="prod-dr-cfn-artifacts-$accountId-ap-southeast-1" BackupVaultName=prod-dr-backup-vault `
  --no-execute-changeset

aws cloudformation deploy --stack-name prod-dr-dr-ecr `
  --template-file .\cloudformation\bootstrap\dr-ecr.yaml `
  --region ap-southeast-1 `
  --parameter-overrides Environment=production RepositoryPrefix=prod `
  --no-execute-changeset
```

Review bằng `aws cloudformation describe-change-set`, rồi mới `execute-change-set` với đúng ARN/name do lệnh trên trả về.

### Phase 1 — package và primary

```powershell
.\cloudformation\scripts\package.ps1 `
  -PrimaryArtifactBucket "prod-dr-cfn-artifacts-$accountId-ap-southeast-2" `
  -DrArtifactBucket "prod-dr-cfn-artifacts-$accountId-ap-southeast-1" `
  -ReleaseVersion "release-2026-09-16.1"

aws cloudformation create-change-set `
  --stack-name prod-dr-primary `
  --change-set-name initial-primary `
  --change-set-type CREATE `
  --template-body file://.cfn-package/primary-packaged.yaml `
  --parameters file://cloudformation/parameters/prod-primary.json `
  --capabilities CAPABILITY_IAM `
  --region ap-southeast-2
```

`ReleaseVersion` trở thành immutable S3 key `releases/<version>/dr-root.yaml`; script từ chối overwrite để disaster không vô tình dùng template mới hơn bản đã test. `prod-primary.json` để `EcsDesiredCount=0`, nên stack có thể tạo task definition/service trước khi image tồn tại mà không pull image.

### Phase 2 — ECR replication và image

Các repository Singapore được tạo trước để ép `IMMUTABLE`, scan-on-push và lifecycle policy; ECR replication không sao chép các thiết lập repository này. Sau khi primary stack tạo ECR replication configuration:

```powershell
.\cloudformation\scripts\publish-images.ps1 -AccountId $accountId -RepositoryPrefix prod -ImageTag v1

aws ecr describe-images --repository-name prod-auth --image-ids imageTag=v1 --region ap-southeast-1
aws ecr describe-images --repository-name prod-product --image-ids imageTag=v1 --region ap-southeast-1
aws ecr describe-images --repository-name prod-order --image-ids imageTag=v1 --region ap-southeast-1
```

Chỉ sau khi cả ba image có ở Singapore, tạo change set update primary với `EcsDesiredCount=1` hoặc `2`, review rồi execute.

### Phase 3–4 — backup và cross-Region copy

Backup plan nằm trong primary root và mặc định chạy mỗi 6 giờ. Có thể tạo on-demand backup từ Console cho LAB. Không bắt đầu DR test trước khi recovery point trạng thái `COMPLETED` xuất hiện tại `prod-dr-backup-vault` ở Singapore.

CLI kiểm tra:

```powershell
aws backup list-recovery-points-by-backup-vault `
  --backup-vault-name prod-dr-backup-vault `
  --by-resource-type RDS `
  --region ap-southeast-1
```

Console: **AWS Backup → Backup vaults → prod-dr-backup-vault → Recovery points** (Region Singapore). Kiểm tra cả backup job và copy job trong **Jobs**.

### Phase 5–6 — DR template và automation

`package.ps1` upload packaged DR root vào immutable release key tại Singapore. Gán URL in ra màn hình vào `DrRuntimeTemplateUrl`; điền thêm `SourceDatabaseArn` từ output primary stack và KMS key ARN từ hai baseline stack trong các parameter files, rồi tạo/review change set automation ở Singapore.

Sau khi automation stack hoàn tất, lấy output `DrEventBusArn` và deploy forwarder tại Sydney:

```powershell
aws cloudformation deploy `
  --stack-name prod-dr-primary-event-forwarder `
  --template-file .\cloudformation\automation\eventbridge-primary.yaml `
  --region ap-southeast-2 `
  --capabilities CAPABILITY_IAM `
  --parameter-overrides ProjectName=prod-dr PrimaryAlarmName=prod-dr-primary-application-unavailable DrEventBusArn=REPLACE_WITH_OUTPUT `
  --no-execute-changeset
```

Confirm email subscription của SNS trước khi test. Một subscription `PendingConfirmation` sẽ không nhận alert.

## 8. Normal-operation verification

1. Route 53 hosted zone chỉ có failover record `PRIMARY` cho application; chưa có `SECONDARY`.
2. `curl http(s)://app.example.com/health` trả `200` từ Sydney.
3. `/auth`, `/product`, `/order` trả service tương ứng.
4. ECS Sydney có desired/running count bằng nhau; ALB có ba target groups healthy.
5. RDS không public; SG inbound chỉ từ ECS SG.
6. Singapore không có stack `prod-dr-runtime-production`, không có DR ALB/NAT/ECS/RDS. Chỉ baseline/automation, backup, ECR và S3 artifacts tồn tại.

Console paths: **CloudFormation → Stacks**, **ECS → Clusters**, **EC2 → Load Balancers/Target Groups**, **RDS → Databases**, **Route 53 → Hosted zones/Health checks**, **CloudWatch → Dashboards/Alarms**.

## 9. DR workflow và false-positive controls

Mỗi service có alarm `HealthyHostCount < 1`, 3 datapoints trong 5 phút, `TreatMissingData=breaching`; composite alarm chính chuyển `ALARM` nếu Auth, Product hoặc Order unavailable. Một datapoint fail không dựng DR. Workflow sau đó:

1. Chờ thêm 90 giây.
2. Lambda đọc lại đúng alarm tại Sydney.
3. Nếu alarm không còn `ALARM`, kết thúc mà không tạo DR.
4. Sau khi DR healthy, đọc alarm thêm lần nữa ngay trước DNS cutover.

State machine timeout được parameter hóa bằng `WorkflowTimeoutSeconds`, mặc định 43.200 giây (12 giờ, tối đa 24 giờ). Lock TTL dùng cùng giới hạn; execution bị stop/timeout không thể chạy release state nhưng execution mới có thể chiếm lock sau khi TTL hết hạn.

Composite target-health hiện bao phủ cả ba service nhưng vẫn chưa bao phủ DNS/TLS hoặc transaction correctness. Production nên bổ sung Synthetics external HTTP, error rate và manual approval/SSM Incident Manager cho cutover có blast radius cao.

## 10. Safe DR test

Mặc định script bật `SkipRoute53Switch=true`:

```powershell
.\cloudformation\scripts\invoke-dr-test.ps1 -StateMachineArn REPLACE_WITH_STATE_MACHINE_ARN
```

Expected milestones trong execution history:

```text
T0 Start -> confirm -> CFN runtime ready (T1)
-> latest recovery point -> RDS restore available (T2)
-> runtime secret -> ECS + 3 target groups healthy (T3)
-> DNS skipped for safe test -> Success
```

Chỉ dùng `-AllowRoute53Switch` trong maintenance window đã được phê duyệt. Khi đó Step Functions tạo SECONDARY alias sau health gate; Route 53 native failover vẫn ưu tiên PRIMARY khi Sydney healthy.

Manual simulation truyền `test_mode` cho restore nên RDS test không bật deletion protection. Alarm production vẫn restore với deletion protection. Workflow dùng lock singleton; execution thứ hai được suppress và thông báo thay vì tạo restore song song. Nếu primary hồi phục sau khi DR đã dựng nhưng trước cutover, tài nguyên được giữ để điều tra và phải cleanup có kiểm soát—không tự động xóa database phục hồi.

## 11. RTO/RPO measurement

Không ghi số giả. Lấy timestamps từ Step Functions execution history và AWS Backup:

- T0: `ExecutionStarted`
- T1: `CREATE_COMPLETE` của root DR stack
- T2: restore job `COMPLETED` và RDS `available`
- T3: Lambda `check-alb` trả cả ba target group healthy
- T4: Route 53 change accepted/INSYNC; cộng ảnh hưởng DNS resolver/cache
- RTO quan sát: `T4 - T0` (hoặc `T3 - T0` khi safe test skip DNS)
- RPO quan sát: failure timestamp trừ `creation_date` của recovery point được chọn

Lưu execution ARN, restore job ID, recovery point ARN và Route 53 change ID làm evidence. AWS Backup không cam kết copy completion time; lịch 6 giờ không đồng nghĩa RPO luôn ≤ 6 giờ.

## 12. Failback

Không tự động failback. Backup & Restore không có replication hai chiều realtime.

```text
Validate/rebuild Sydney
-> chọn phương án đồng bộ dữ liệu từ Singapore về Sydney
-> freeze writes hoặc kiểm soát delta
-> application/data validation
-> controlled DNS switch về PRIMARY
-> monitor error/latency/data integrity
-> scale DR to zero
-> snapshot/final backup
-> delete restored RDS rồi delete DR runtime stack
```

Phương án sync phụ thuộc downtime và data volume: logical dump/restore cho LAB; DMS/replication tạm thời cho production lớn. Phải có change approval và rollback point trước cutback.

## 13. Cost optimization

Standby Singapore chỉ phát sinh chính ở backup copy/storage, ECR image storage và S3 template storage. IAM/EventBridge/SNS/Step Functions gần như không đáng kể khi idle. Không có DR RDS, ALB, NAT hay Fargate tasks trước sự cố.

Runtime DR dùng một NAT Gateway để đơn giản và rút ngắn đường phục hồi. Đây là single-AZ egress dependency; production có thể chọn NAT per AZ. VPC endpoints cho ECR API/DKR, S3, Logs và Secrets Manager tránh NAT path nhưng nhiều interface endpoints có hourly cost/complexity cao hơn cho một LAB ngắn. Vì tất cả chỉ tồn tại trong disaster, single NAT là trade-off mặc định hợp lý cho project này.

## 14. Troubleshooting

- **Stack CREATE_FAILED:** dùng `aws cloudformation describe-events --stack-name NAME --filters FailedEvents=true --region REGION`; sửa event có lỗi cụ thể, không coi “Resource creation cancelled” là root cause.
- **Nested TemplateURL AccessDenied:** kiểm tra packaged URL, bucket Region, object tồn tại, execution role có `s3:GetObject`, bucket policy không deny TLS/principal.
- **Step Functions AccessDenied:** xác định state thất bại và action/ARN cụ thể; không gắn FullAccess. Kiểm tra `iam:PassRole` và `iam:PassedToService`.
- **Recovery point not found:** phải ở `prod-dr-backup-vault`, Region Singapore, resource type `RDS`, status `COMPLETED`; kiểm tra copy job/KMS grant.
- **Restore failed:** xem AWS Backup restore job status message, restore metadata, subnet group, SG, DB class availability và KMS permissions.
- **RDS restore timeout:** không retry tạo restore mới mù quáng; kiểm tra job ID hiện tại và RDS events. Idempotency token ngăn Lambda retry tạo duplicate.
- **ECS CannotPullContainerError:** xác nhận tag tồn tại ở Singapore, private subnet route qua NAT, SG outbound 443 và execution role ECR permissions.
- **ECS cannot read secret:** runtime secret phải có `host`, `username`, `password`; execution role phải match secret ARN suffix.
- **ECS cannot connect RDS:** kiểm tra DB status/endpoint, DB SG từ ECS SG port 5432, subnet routes/NACL và TLS/application retry.
- **ALB unhealthy:** container port/path `/health`, task logs, service events, SG ALB→ECS và health grace period.
- **Route 53 update failed:** Hosted Zone ID/domain phải đúng; PRIMARY và SECONDARY cùng name/type, unique `SetIdentifier`; role cần quyền đúng hosted-zone ARN.
- **SNS không nhận mail:** confirm subscription, kiểm tra topic encryption/policy và delivery status.
- **EventBridge không trigger:** test exact event pattern/alarm name, kiểm tra Sydney forwarder metrics, Singapore custom bus rule và execution role.

## 15. Cleanup — destructive, cần xác nhận riêng

Không chạy cleanup trên production thật chỉ vì LAB kết thúc. Trước mỗi delete, tạo và review kế hoạch/resource inventory.

Thứ tự an toàn cho một DR test:

1. Xóa SECONDARY Route 53 record nếu test đã cutover; xác minh PRIMARY đang healthy.
2. Scale DR ECS về 0.
3. Tạo final snapshot nếu cần. Disaster restore bật deletion protection còn manual test không bật; chỉ sau approval cleanup mới vô hiệu hóa protection khi cần và xóa DB **trước** DR stack, nếu không DB ENI/SG sẽ chặn stack deletion.
4. Delete `prod-dr-runtime-production` và chờ `DELETE_COMPLETE`.
5. Chỉ khi ngừng toàn bộ LAB: delete primary EventBridge forwarder, automation stack, rồi baseline artifact objects/buckets.
6. Recovery points/vault, primary RDS và primary stack được giữ mặc định. Chỉ xóa bằng một change được phê duyệt; KMS keys, buckets, vaults và RDS có retention/deletion protection chủ ý.

Không dùng `--force`, không xóa recovery point production mù quáng, và không vô hiệu hóa deletion protection chỉ để làm cho lệnh destroy “chạy được”.

Script cleanup có guard thực hiện đúng thứ tự DNS gate → ECS về 0 → final snapshot/RDS delete → runtime stack delete:

```powershell
.\cloudformation\scripts\cleanup-dr-test.ps1 `
  -ConfirmCleanup `
  -HostedZoneId REPLACE_WITH_HOSTED_ZONE_ID `
  -DomainName app.example.com
```

Script từ chối chạy nếu SECONDARY record còn tồn tại. Với disaster restore có deletion protection, phải thêm `-AllowDisableDeletionProtection` sau approval riêng. Mặc định script tạo final snapshot; `-SkipFinalSnapshot` là lựa chọn phá hủy dữ liệu và không nên dùng ngoài test disposable. `DeletionPolicy: Retain` cố ý giữ artifact buckets, backup vaults, KMS keys, ECR repositories và DynamoDB lock table sau khi xóa stack; các resource này cần inventory/approval riêng nếu muốn xóa vật lý.
