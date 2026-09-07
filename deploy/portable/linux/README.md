# LibreChat 0cherry — Linux 이동식 배포

이 묶음은 x86-64 Linux의 Docker Engine과 Docker Compose v2에서 실행해.
대상 서버에 Node.js, npm, Git을 설치하거나 LibreChat 소스를 빌드할 필요는 없어.
포함된 이미지를 사용하므로 최초 실행에 인터넷은 필요 없지만 Qwen 서버에는 접근할 수 있어야 해.

포함: Qwen 추론 ON/OFF 기능이 적용된 LibreChat, MongoDB, Meilisearch.
제외: 기존 사용자·대화·업로드·비밀키, 모델 가중치/서빙, 문서 RAG, 관리자 패널.

첨부파일은 모델 capability에 맞춰 처리해. `VL`, `Vision` 등 비전 모델로 판별되면 이미지를
네이티브 입력으로 보내고, 일반 모델에서는 직접 이미지 입력을 막아. PDF와 문서는 기본적으로
LibreChat 내장 파서로 텍스트를 추출해 전달하므로 OpenAI 전용 `type: file` 지원이 필요 없어.
`librechat.yaml`의 `fileConfig.endpoints.<name>.modelCapabilities`에서 기본값과 모델별 패턴을
재정의할 수 있어.

## 1. 요구사항

- x86-64 Linux
- Docker Engine
- Docker Compose v2 플러그인
- 권장 여유 RAM 8GB 이상, 여유 디스크 15GB 이상
- 서버와 컨테이너에서 Qwen 주소에 접근할 수 있는 네트워크 경로

Docker 설치는 배포판별 [공식 Docker Engine 안내](https://docs.docker.com/engine/install/)를 따라.
Docker 데몬 소켓 접근 권한은 사실상 관리자 권한이므로 신뢰하는 운영 계정만 사용해.

## 2. 압축 해제와 최초 실행

파일 이름은 실제 받은 버전으로 바꿔줘.

```bash
sha256sum -c librechat-0cherry-<commit>-linux-amd64.tar.gz.sha256
tar -xzf librechat-0cherry-<commit>-linux-amd64.tar.gz
cd librechat-0cherry-<commit>-linux-amd64

./setup.sh --server-url http://192.168.0.50:3080
./run.sh start
./run.sh bootstrap-admin
```

`192.168.0.50`은 LibreChat을 실행하는 Linux 서버의 실제 IP로 바꿔.
기본 Qwen 주소는 `http://10.10.10.200:19640/v1`, 모델은 `Qwen/Qwen3.6-27B`야.
다른 PC에서는 설정한 URL로 접속하면 돼.

설치 환경이 실행 권한을 제거했다면 한 번만 실행해:

```bash
chmod 755 setup.sh run.sh
```

설정 스크립트는 새 랜덤 키를 만들고 기존 `.env`나 `librechat.yaml`을 덮어쓰지 않아.
회원가입은 관리자를 만들 때까지 닫혀 있어. `bootstrap-admin`으로 첫 관리자 계정을 만들면
회원가입이 자동으로 열리고, 이후 가입한 계정은 관리자 승인 전까지 로그인할 수 없어.
관리자는 LibreChat의 **설정 → 일반 → 관리자 → 가입 승인**에서 승인하면 돼.
상위 LibreChat 계정 생성 도구는 비밀번호 입력을 화면에 표시하므로 화면 공유나 녹화 없이 실행해.

### 주소나 포트 변경

```bash
./setup.sh \
  --server-url http://192.168.0.50:8080 \
  --port 8080 \
  --qwen-url http://10.10.10.200:19640/v1 \
  --model Qwen/Qwen3.6-27B
```

최초 설정 후에는 `.env`의 `HTTP_PORT`, `DOMAIN_CLIENT`, `DOMAIN_SERVER`를 함께 바꿔.
Qwen 주소는 `librechat.yaml`의 `baseURL`과 `allowedAddresses`를 함께 바꿔.
Qwen 서버에 인증이 필요하면 `.env`의 `QWEN_API_KEY`를 수정해.
설정 변경 후 `./run.sh stop && ./run.sh start`로 재시작해.

## 3. 운영 명령

```bash
./run.sh status
./run.sh logs
./run.sh check
./run.sh stop
./run.sh start
./run.sh bootstrap-admin
./run.sh create-user
```

`check`는 앱 HTTP 상태와 Qwen `/models` 접근을 검사해. 추론 요청은 보내지 않아.
시작 시 이미지 파일의 SHA256과 설치된 이미지 ID를 검사하며 자동 다운로드하지 않아.
이미지를 다시 설치하려면 `./run.sh load`를 실행해.

## 4. 방화벽과 보안

기본적으로 `0.0.0.0:3080`에서 수신하지만 방화벽은 자동으로 바꾸지 않아.
신뢰하는 내부망에서만 3080/TCP를 허용해. HTTP는 로그인 정보와 대화를 암호화하지 않으므로
인터넷에 직접 공개하면 안 돼. 외부 접속은 HTTPS 리버스 프록시와 별도 접근 제어를 구성해.
프록시만 접근하게 하려면 최초 설정에 `--bind-address 127.0.0.1`을 추가해.

MongoDB와 Meilisearch의 호스트 포트는 열지 않아. 두 서비스는 프로젝트 내부 네트워크에서만 접근해.
인증 없이 실행되는 DB 네트워크에 신뢰하지 않는 컨테이너를 연결하지 마.

## 5. 데이터 유지

- Docker Compose 프로젝트 이름은 기본적으로 `librechat-portable`이야.
- 데이터는 Docker named volume에 있으며 배포 폴더를 옮겨도 같은 프로젝트 이름이면 유지돼.
- `./run.sh stop`은 데이터를 지우지 않아.
- `docker compose down -v`나 volume 삭제는 계정과 대화를 지울 수 있으므로 실행하지 마.
- 백업에는 MongoDB 덤프, uploads/images/app-data/skills volume, `.env`, `librechat.yaml`이 필요해.
- `.env`의 암호화 키를 잃으면 저장된 자격증명을 복구하지 못할 수 있어.
- 컨테이너는 `unless-stopped`로 재시작하지만 Docker 서비스 자체도 부팅 시 활성화해야 해.

이 묶음은 신규 설치용이며 기존 Windows 설치의 계정·대화 자동 이전은 포함하지 않아.
