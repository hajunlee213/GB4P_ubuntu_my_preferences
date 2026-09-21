# PAM 지문인식(fprintd) 시도 횟수 및 타임아웃 최적화 (`pam_fprint_tuning.sh`)

우분투에서 지문 인증(PAM fprintd) 시 기본적으로 적용되는 빡빡한 재시도 및 타임아웃 제한을 해제하고, 업스트림 표준 규격(3회 시도, 30초 타임아웃)으로 복원하는 스크립트입니다.

---

## 1. 배경 및 목적

우분투/데비안 공식 `libpam-fprintd` 패키지는 `/usr/share/pam-configs/fprintd` 기본 프로필에 `max-tries=1 timeout=10 # debug` 옵션을 하드코딩하여 배포합니다.

* **발생하는 문제점**:
  * 지문 센서에 손가락을 살짝 빗맞추거나 각도가 어긋나 1회 인식에 실패하면 즉시 비밀번호 입력으로 강제 전환됩니다.
  * 10초 이내에 지문을 대지 못하면 곧바로 타임아웃되어 비밀번호 프롬프트로 넘어갑니다.
* **패키지 메인테이너의 의도**:
  * 터미널 환경(`sudo`, `su` 등)에서 지문을 사용하지 않고 비밀번호 입력을 선호하는 사용자가 대기하는 시간을 단축하기 위해 의도적으로 매우 빡빡하게 제한해 둔 것입니다.
* **해결책**:
  * 지문 인식을 실사용하는 환경에 맞춰 업스트림 `pam_fprintd` 표준인 **최대 3회 시도, 30초 대기**로 설정하여 실사용 편의성을 대폭 향상합니다.

---

## 2. 수정 및 생성되는 시스템 경로

| 경로 | 역할 | 변경 내용 |
| :--- | :--- | :--- |
| `configs/pam/fprintd` | 저장소 내 PAM 프로필 템플릿 | `pam_fprintd.so max-tries=3 timeout=30` 정의 |
| `/usr/share/pam-configs/fprintd` | 시스템 PAM 프로필 정의 파일 | `max-tries=3 timeout=30`으로 갱신 |
| `/etc/pam.d/common-auth` | 공통 PAM 인증 스택 설정 | `pam-auth-update`에 의해 `pam_fprintd.so max-tries=3 timeout=30`으로 자동 재생성 |

---

## 3. 주요 파라미터 및 원리

`man pam_fprintd`에 명시된 업스트림 표준 파라미터:

* **`max-tries=3`**:
  * 지문 인증 실패를 반환하기 전까지 허용되는 최대 지문 스캔 시도 횟수입니다.
  * 업스트림 기본값이 `3`이며, 1회 실패하더라도 2회 더 재시도할 수 있어 인식 오류 시 편의성이 크게 개선됩니다.
* **`timeout=30`**:
  * 지문 입력을 대기하는 시간(초)입니다.
  * 업스트림 기본값이 `30`초이며, 30초 동안 지문 입력을 여유롭게 대기합니다.

---

## 4. 사전 요구사항 및 의존성

* **패키지**: `libpam-fprintd`, `fprintd`
* **권한**: root 권한 (`sudo`)

---

## 5. 실행 방법

```bash
sudo ./pam_fprint_tuning.sh
```

---

## 6. 수동 확인 및 롤백 (원상 복구) 방법

### 적용 상태 확인
```bash
grep "pam_fprintd" /etc/pam.d/common-auth
```
출력에 `max-tries=3 timeout=30`이 포함되어 있으면 정상 적용된 상태입니다.

### 순정 우분투 기본값(1회, 10초)으로 롤백
```bash
sudo sed -i 's/pam_fprintd\.so.*/pam_fprintd.so max-tries=1 timeout=10 # debug/' /usr/share/pam-configs/fprintd
sudo pam-auth-update --package
```
