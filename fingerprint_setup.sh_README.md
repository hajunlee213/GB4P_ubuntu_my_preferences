# 지문인식 센서 드라이버 & PAM 원클릭 복원 (`fingerprint_setup.sh`)

삼성 갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK / Egis `1c7a:05a1`)의 지문인식 센서에서 발생하는 재부팅 시 지문 유실, 화면 잠금/절전 복귀 시 센서 먹통(`65 E0`), `fprintd` 데몬 크래시 문제를 해결한 **SDCP Version 2 드라이버**와 **PAM 최적화(3회/30초)**를 원클릭으로 복원하는 스크립트입니다.

---

## 1. 배경 및 목적

갤럭시 북4 프로에 내장된 이지스테크(EgisTec) MoC 지문 센서(`1c7a:05a1`)는 SDCP(Secure Device Connection Protocol)를 통해 호스트와 암호화 통신을 수행합니다. 그러나 순정 우분투 및 기본 오픈소스 드라이버에서는 다음과 같은 심각한 문제들이 존재합니다:

1. **재부팅 시 등록 지문 유실 (Host Key 파기 버그)**:
   - 드라이버가 커널의 `boot_id` 변경을 감지하면 기존 Host Key 캐시를 삭제하고 새 키를 생성함.
   - 센서는 지문 템플릿을 Host Key에 암호학적으로 묶어두므로, 키가 바뀌면 센서가 주인이 바뀐 것으로 판단하여 기존 지문 접근을 거부함.
2. **화면 잠금 / 절전 복귀 시 센서 먹통 (`65 E0` 에러)**:
   - 화면이 꺼지거나 USB 절전 모드로 진입 시 센서 하드웨어가 자체 세션을 잃어버림.
   - 드라이버는 이전 세션이 유지된 것으로 착각하여 기존 세션으로 통신을 시도하다 불일치 에러 발생.
3. **취소 시 `fprintd` 데몬 크래시 (자원 누수)**:
   - 지문 인증 도중 화면이 꺼지거나 취소될 때 상태 머신(`task_ssm`)이 정리되지 않아 다음번 지문 요청 시 데몬이 즉시 비정상 종료됨.
4. **우분투 PAM의 가혹한 기본 제한**:
   - 우분투 기본 패키지는 터미널 대기를 줄이기 위해 1회 실패 시 즉시 비밀번호로 넘어가고 10초 만에 타임아웃됨.

---

## 2. 수정 및 생성되는 시스템 경로

| 경로 | 역할 | 변경 내용 |
| :--- | :--- | :--- |
| `configs/libfprint/libfprint-2.so.2.0.0` | 저장소 내 Version 2 패치 바이너리 | 패치 빌드된 공유 라이브러리 |
| `/usr/local/lib/x86_64-linux-gnu/libfprint-2.so*` | 시스템 적용 경로 | 패치 라이브러리 및 심볼릭 링크 배포 |
| `configs/pam/fprintd` | 저장소 내 PAM 프로필 템플릿 | `pam_fprintd.so max-tries=3 timeout=30` |
| `/usr/share/pam-configs/fprintd` | 시스템 PAM 프로필 | `max-tries=3 timeout=30`으로 갱신 |
| `/etc/pam.d/common-auth` | 공통 PAM 스택 | 3회 시도, 30초 대기 자동 반영 |
| `/var/lib/fprint/sdcp-claim-*` | 세션 키 캐시 | 재부팅/초기화 시 이전 휘발성 세션 정리 |

---

## 3. 주요 파라미터 및 원리 (Version 1 vs Version 2)

### Version 1 (재부팅 베이스라인)
* **호스트 키 영구 보존**: `boot_id` 불일치 시 캐시 키를 지우는 로직 제거.
* **만료 시간 무제한**: `claim_expiration_seconds = -1` (24시간 자동 만료 차단).
* *한계*: 절전 복귀 시 세션 재사용 시도로 인한 `65 E0` 에러 및 인증 취소 시 데몬 크래시 상존.

### Version 2 (현재 실사용 최신 버전 - Full Fix)
* **`task_ssm` 누수 해제 (`egismoc.c`)**:
  * `egismoc_close` 시 잔여 상태 머신이 있을 경우 `fpi_ssm_free` 및 `NULL` 초기화를 강제하여 데몬 크래시 완벽 차단.
* **강제 SDCP 재연결 (`fpi-sdcp-device.c`)**:
  * 캐시 로드 시 무조건 `priv->is_connected = FALSE`로 설정.
  * `fprintd`가 깨어날 때마다(화면 잠금 해제, 절전 복귀 시) 영구 보존된 Host Key를 유지한 채 **항상 새로운 보안 세션(`SDCP Connect`)을 협상**하여 센서 기억상실 문제 완벽 해결.
* **PAM 3회 시도 / 30초 타임아웃 연동**:
  * 살짝 빗맞거나 각도가 안 맞아도 3회까지 여유롭게 재시도 가능.

---

## 4. 사전 요구사항 및 의존성

* **패키지**: `fprintd`, `libpam-fprintd` (스크립트 실행 시 자동 설치됨)
* **하드웨어**: Egis MoC 센서 (`1c7a:05a1` 등)
* **권한**: root 권한 (`sudo`)

---

## 5. 실행 및 사용 방법

### 원클릭 복원
```bash
sudo ./fingerprint_setup.sh
```

### 지문 등록 및 테스트
```bash
# 새 지문 등록 (지시에 따라 손가락 반복 태그)
fprintd-enroll

# 등록된 지문 확인
fprintd-list $USER

# 지문 인증 테스트
fprintd-verify
```

---

## 6. 순정 롤백 (원상 복구) 방법

```bash
sudo ./fingerprint_setup.sh --restore
```
* `/usr/local/lib/x86_64-linux-gnu/libfprint-2.so*`를 제거하고 `ldconfig`를 수행하여 우분투 기본 패키지(`libfprint-2.so`)로 즉시 복원합니다.
* PAM 설정을 우분투 순정 기본값(`max-tries=1 timeout=10`)으로 되돌립니다.
