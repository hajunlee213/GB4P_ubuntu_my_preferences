# ⚡ Issue Analysis & Fix Guide: 전원 전환 스크립트 및 udev 연동 개선 가이드

> **문서 목적:** AC/DC 전원 자동 전환 udev 룰과 `handle_power_change.sh` 스크립트가 절전 모드(Suspend/Resume) 및 충전기 연결/분리 시 일으키는 **중복 병렬 실행, D-Bus 과부하, AppArmor 차단 문제**의 분석과 해결 방안을 정리한 인계용 문서입니다.

---

## 📌 1. 현재 발생 중인 문제 상황 (Observed Issues)

노트북 절전 모드 복귀(Resume) 또는 충전기 연결/해제 시 다음과 같은 현상이 발생합니다:

1. **스크립트 3~4개 동시 병렬 실행:**
   * 절전에서 깨어나거나 전원 상태가 변할 때 `handle_power_change.sh`가 1마이크로초 간격으로 **3~4회 동시에 실행**됨.
2. **D-Bus 및 시스템 설정 충돌:**
   * 16개 CPU 코어의 sysfs 파일과 `powerprofilesctl`(GNOME 전원 모드)에 D-Bus 요청이 연속 난사되어 절전 복귀 시 GNOME Shell / Mutter가 버벅이거나 D-Bus 타임아웃 유발.
3. **AppArmor 보안 거부 로그 대량 발생:**
   * udev 환경에서 `sudo -u hajun notify-send`로 일반 사용자 세션 D-Bus(`run/user/1000/bus`)에 접근하려다 AppArmor에 의해 차단(`DENIED`)됨.

### 📋 실제 시스템 로그 기록 (`journalctl`)

```text
# 1. 16:51:37 - 동일한 밀리초에 sudo 세션이 3개 동시 생성되어 알림 실행
16:51:37 sudo[64883]: pam_unix(sudo:session): opened for user hajun by (uid=0) COMMAND=/usr/bin/notify-send ...
16:51:37 sudo[64885]: pam_unix(sudo:session): opened for user hajun by (uid=0) COMMAND=/usr/bin/notify-send ...
16:51:37 sudo[64886]: pam_unix(sudo:session): opened for user hajun by (uid=0) COMMAND=/usr/bin/notify-send ...

# 2. udev에서 사용자 버스로 접근하려다 AppArmor 차단 (연속 9건)
16:51:37 kernel: audit: apparmor="DENIED" operation="connect" class="file" profile="notify-send" name="run/user/1000/bus" pid=64890 comm="notify-send"
```

---

## 🔍 2. 근본 원인 분석 (Root Causes)

### ① udev 룰 필터링 누락 (4개 장치 동시 트리거)
* **현재 룰 ([`/etc/udev/rules.d/99-power-profile-switch.rules`](file:///etc/udev/rules.d/99-power-profile-switch.rules)):**
  ```udev
  SUBSYSTEM=="power_supply", ACTION=="change", RUN+="/usr/bin/bash /home/hajun/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh"
  ```
* 시스템의 `/sys/class/power_supply/`에는 4개 장치가 존재합니다:
  * `ADP1` (AC 충전기 어댑터)
  * `BAT1` (배터리)
  * `ucsi-source-psy-USBC000:001` (Type-C 1번 포트)
  * `ucsi-source-psy-USBC000:002` (Type-C 2번 포트)
* `SUBSYSTEM=="power_supply"`로만 매칭하면 전원 상태 변화나 절전 복귀 시 **4개 장치가 각각 이벤트를 발생**시켜 스크립트가 4번 실행됩니다.

### ② 스크립트 내 중복 실행 방지(Lock / Debounce) 부재
* `handle_power_change.sh`에 파일 락(`flock`)이나 디바운스가 없어, 동시에 뜬 프로세스들이 각자 16개 코어 sysfs 쓰기, `powerprofilesctl` D-Bus 호출, `notify-send`를 중복 수행합니다.

### ③ udev 내 직접 GUI 알림(`notify-send`) 실행의 구조적 한계
* `systemd-udevd`는 격리된 샌드박스에서 실행되므로 일반 사용자 세션 버스(`unix:path=/run/user/1000/bus`) 접근이 AppArmor 정책상 차단됩니다.

---

## 🛠️ 3. 권장 수정 사항 (Action Plan)

### 수정 1. udev 룰 특정 장치 한정 (`/etc/udev/rules.d/99-power-profile-switch.rules`)
배터리/USB-C 포트의 잔여 이벤트를 무시하고, 오직 **AC 어댑터(`ADP1`)의 전원 변경 이벤트만 감지**하도록 수정:

```udev
SUBSYSTEM=="power_supply", KERNEL=="ADP1", ACTION=="change", RUN+="/usr/bin/bash /home/hajun/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh"
```
*(수정 후 `sudo udevadm control --reload-rules` 적용 필요)*

---

### 수정 2. `handle_power_change.sh`에 `flock` (중복 실행 방지 락) 추가
스크립트 맨 위에 파일 락을 걸어 1초 이내에 연속으로 들어오는 중복 실행은 즉시 무시/종료하도록 보완:

```bash
#!/usr/bin/env bash
# ==============================================================================
# 중복 실행 방지 (0.5초 디바운스 락)
# ==============================================================================
LOCKFILE="/tmp/handle_power_change.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    exit 0
fi

# 짧은 디바운스 대기 (하드웨어 sysfs 상태 안정화)
sleep 0.2
```

---

### 수정 3. GUI 알림 안전 처리 (AppArmor/D-Bus 에러 방지)
`notify-send` 호출 시 오류가 나도 시스템에 부하를 주지 않도록 하거나, 사용자 세션 서비스/systemd-notify 방식으로 안전하게 분리.

---

## 📁 4. 관련 파일 위치 맵

| 파일 경로 | 설명 |
| :--- | :--- |
| `/etc/udev/rules.d/99-power-profile-switch.rules` | 전원 변경 감지 udev 룰 |
| `/home/hajun/Desktop/OneClickScripts/PowerOptions/handle_power_change.sh` | 실제 AC/DC 전환 로직 스크립트 |
| `/home/hajun/Desktop/OneClickScripts/PowerOptions/ISSUE_AND_FIX_GUIDE_POWER_SWITCH.md` | **(본 문서)** 문제 분석 및 수정 인계서 |
