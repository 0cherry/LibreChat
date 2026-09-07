# LibreChat 0cherry — Windows 이동식 배포

이 묶음은 Windows PC의 **Docker Desktop / Linux containers / x86-64** 환경에서 실행해.
대상 PC에 Node.js, npm, Git을 설치하거나 소스를 빌드할 필요는 없어.
Docker 설치가 끝나 있으면 포함된 이미지로 인터넷 없이 시작할 수 있어.
단, Qwen 서버에 대한 내부망 연결은 계속 필요해.

포함: Qwen 추론 ON/OFF 기능을 적용한 LibreChat, MongoDB, 대화 검색(Meilisearch).
제외: 기존 사용자·대화·업로드·비밀키, 모델 가중치/서빙, 문서 RAG, 별도 관리자 패널,
외부 MCP/인터넷 서비스 및 해당 서비스의 의존성.

첨부파일은 모델 capability에 맞춰 처리해. 비전 모델로 판별된 경우에만 이미지를 네이티브
입력으로 보내고, PDF와 문서는 LibreChat 내장 파서로 텍스트를 추출해 전달해.
동작은 `librechat.yaml`의 `fileConfig.endpoints.<name>.modelCapabilities`에서 모델별로 재정의할 수 있어.

## 1. 서버 PC 준비

- Windows 10/11 x86-64와 WSL 2 기반 Docker Desktop을 준비하고 **Linux containers**로 실행해.
- Docker Desktop 설치/지원 조건은 [공식 Windows 설치 안내](https://docs.docker.com/desktop/setup/install/windows-install/)를 확인해.
  Windows Server 운영체제라면 이 경로가 아니라 Linux VM + Docker Engine 등이 필요해.
- 권장 출발점: 여유 RAM 8GB 이상, 여유 디스크 15GB 이상. 동시 사용자/데이터량에 따라 늘려야 해.
  모델은 별도 서버에서 실행하므로 이 PC의 GPU는 필요 없어.
- 서버 PC 및 Docker 컨테이너에서 Qwen 주소에 접근할 수 있어야 해.
  기본값은 `http://10.10.10.200:19640/v1`, 모델 ID는 `Qwen/Qwen3.6-27B`야.

## 2. 복사·압축 해제

생성된 `librechat-0cherry-<commit>-windows-amd64.tar.gz`와 같은 이름의 `.sha256`를 복사해.
PowerShell에서 해시를 비교한 후 압축을 풀어. 아래 파일 이름은 실제 이름으로 바꿔줘.

```powershell
Get-FileHash .\librechat-0cherry-<commit>-windows-amd64.tar.gz -Algorithm SHA256
Get-Content .\librechat-0cherry-<commit>-windows-amd64.tar.gz.sha256
tar -xzf .\librechat-0cherry-<commit>-windows-amd64.tar.gz
cd .\librechat-0cherry-<commit>-windows-amd64
```

압축 파일 대신 **배포 폴더 전체**를 복사해도 돼. `images.tar`를 빠뜨리지 마.
설정 파일이 있는 폴더는 일반 사용자 공유 폴더에 두지 마.

## 3. 최초 설정·시작

아래 `192.168.0.50`은 **LibreChat을 실행할 새 서버 PC의 실제 IP**로 바꿔줘.
Qwen 서버 IP가 아니라 브라우저로 접속할 PC의 IP야.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ServerUrl "http://192.168.0.50:3080"
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 bootstrap-admin
```

실행 정책 우회는 해당 PowerShell 프로세스에만 적용돼. 회사 정책으로 차단되면 관리자에게 확인해.
첫 시작은 이미지 로드와 DB 초기화 때문에 몇 분 걸릴 수 있어.
회원가입은 관리자를 만들 때까지 닫혀 있어. `bootstrap-admin`에서 첫 관리자 계정을 만들면
회원가입이 자동으로 열리고, 이후 가입한 계정은 관리자 승인 전까지 로그인할 수 없어.
관리자는 LibreChat의 **설정 → 일반 → 관리자 → 가입 승인**에서 승인하면 돼.
이메일 서비스는 포함하지 않아. 기본적으로 이메일 인증을 완료한 로컬 계정을 만들면 돼.
주의: 현재 upstream 계정 생성 CLI는 비밀번호 입력을 화면에 표시하므로 녹화/화면 공유 없이 실행해.
설정 스크립트는 랜덤 키를 생성하고, 기존 `.env`나 `librechat.yaml`을 덮어쓰지 않아.

다른 PC에서 `http://192.168.0.50:3080`에 접속하고 **Qwen Local → 매개변수 → Qwen Thinking**을 조절해.

### 포트·모델 변경

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ServerUrl "http://192.168.0.50:8080" -Port 8080 -QwenUrl "http://10.10.10.200:19640/v1" -Model "Qwen/Qwen3.6-27B"
```

위 명령은 최초 설정 전에만 사용해. 설정 후에는 `.env`에서 `HTTP_PORT`,
`DOMAIN_CLIENT`, `DOMAIN_SERVER`를 함께 바꾸고 `run.ps1 start`를 다시 실행해.
Qwen 주소 변경 시 `librechat.yaml`의 `baseURL`과 `allowedAddresses`를 함께 바꿔줘.
Qwen 서버가 인증을 요구하면 `.env`의 `QWEN_API_KEY`를 수정해.
YAML만 수정했을 때는 `run.ps1 stop` → `run.ps1 start`로 재시작해.

## 4. 방화벽·노출 범위

스크립트는 방화벽 설정을 자동으로 변경하지 않아.
회사 정책을 확인하고, 필요한 경우 **서버의 관리자 PowerShell**에서 접근할 내부망만 허용해.
다음 예시의 대역과 포트는 실제 환경으로 바꿔줘.

```powershell
New-NetFirewallRule -DisplayName "LibreChat LAN 3080" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 3080 -RemoteAddress 192.168.0.0/24 -Profile Domain,Private
```

HTTP는 로그인 정보와 대화를 암호화하지 않아. 기본 묶음은 신뢰하는 내부망 테스트용이야.
인터넷에 직접 공개하지 마. 운영/외부 접속은 별도 HTTPS 리버스 프록시 및 접근 제어가 필요해.
로컬 프록시만 허용하려면 최초 설정에 `-BindAddress 127.0.0.1`을 지정해.
MongoDB와 Meilisearch는 호스트 포트를 열지 않아. DB는 Docker 내부 네트워크에서 인증 없이 동작하므로
이 프로젝트 네트워크에 신뢰하지 않는 컨테이너를 연결하지 마.

## 5. 운영 명령

```powershell
.\run.ps1 status
.\run.ps1 logs
.\run.ps1 check
.\run.ps1 stop
.\run.ps1 start
.\run.ps1 bootstrap-admin
.\run.ps1 create-user
```

스크립트 실행이 차단되면 앞 예시처럼 `powershell -NoProfile -ExecutionPolicy Bypass -File`을 붙여줘.
`check`는 컨테이너 안에서 앱 상태와 Qwen `/models` 접근을 확인해. 모델 추론 요청은 보내지 않아.
HTTP 401은 API 키, 연결 시간 초과는 라우팅/방화벽, 모델 오류는 서버의 실제 모델 ID를 확인해.

이미지는 `manifest.json`의 ID와 대조하고, 로드 전에 `images.tar` SHA256을 검증해.
일반 시작은 이미 설치된 이미지를 재사용하며 자동 다운로드/업데이트하지 않아.
`run.ps1 load`로 묶음의 이미지를 다시 로드할 수 있어.

## 6. 데이터 유지·재부팅

- 기본 Compose 프로젝트 이름은 `librechat-portable`이야. 같은 PC에서 배포 폴더 위치를 바꿔도 같은 프로젝트 이름을 유지해.
- 데이터는 Docker named volume에 있어. 배포 폴더만 복사하면 **대화/계정 데이터는 따라가지 않아**.
- `stop`은 데이터를 삭제하지 않아. `docker compose down -v`, Docker 초기화, volume 삭제는 하지 마.
- 백업에는 MongoDB 덤프, uploads/images/app-data/skills 볼륨, 서버의 `.env`와 `librechat.yaml`이 필요해.
  이 묶음은 신규 설치용이며 기존 데이터 이전/자동 백업은 포함하지 않아.
- `.env`의 암호화 키를 잃거나 재생성하면 저장된 자격증명을 복구하지 못할 수 있어.
- `unless-stopped` 정책으로 Docker 엔진 재시작 시 서비스가 다시 올라와.
  Windows에서는 Docker Desktop의 로그인 시 시작 설정도 확인해. 명시적으로 `stop`한 서비스는 `start`가 필요해.
  로그인 없이 부팅부터 운영해야 하는 서버라면 별도 서비스 운영 구성을 검토해야 해.

## 개발 PC에서 새 묶음 생성

저장소의 `deploy/portable/build.ps1`을 실행해. 앱 소스는 먼저 커밋해야 해.
스크립트는 `git archive HEAD`로 로컬 데이터가 없는 빌드 컨텍스트를 만들고,
Docker 이미지 3개와 실행 파일을 `artifacts/` 아래에 생성해.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\portable\build.ps1
# Docker Engine이 Ubuntu WSL에 있는 개발 PC:
powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\portable\build.ps1 -WslDistro Ubuntu-24.04
```

개발 PC에는 Git, tar, Docker Compose v2와 빌드용 인터넷 연결이 필요해.
실패 시 중간 산출물은 보존해. 같은 이름의 출력이 이미 있으면 덮어쓰지 않고 중단해.
검증된 동일 커밋 이미지가 이미 있으면 `-SkipBuild`로 다시 패키징할 수 있어.
빌드는 잠금 파일을 사용하고 의존 서비스 버전을 고정하지만, OS 패키지까지 비트 단위로 재현하는 빌드는 아니야.
실제 이미지 ID와 소스 커밋은 각 묶음의 `manifest.json`에 기록돼.
