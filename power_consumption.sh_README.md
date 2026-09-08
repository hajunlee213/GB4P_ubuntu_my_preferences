# power_consumption.sh 설명 문서

이 문서는 **[`power_consumption.sh`](./power_consumption.sh)** 스크립트가 적용하는 패치 내용, 동작 원리, 설정 파일 및 롤백 방법을 상세히 설명합니다.

---

## 1. 배경 및 해결하려는 문제

삼성 갤럭시 북4 프로(GB4P, Intel Core Ultra / Meteor Lake 아키텍처)는 고해상도 OLED 디스플레이와 다핵 하이브리드 CPU를 탑재하고 있어 리눅스 우분투 기본 환경에서 다음과 같은 전력 및 발열 문제가 발생합니다:

1. **NVMe SSD의 잦은 웨이크업(Wakeup)으로 인한 배터리 소모**:
   - 리눅스 기본 커널 설정에서는 디스크 캐시 dirty writeback 주기가 5초 단위로 짧게 돌아가 SSD가 절전 상태(APST / NVMe low power state)에 머무르지 못하고 자주 깨어납니다.
2. **Meteor Lake 하이브리드 CPU(P + E + LP-E)의 고발열 구조**:
   - P코어의 하이퍼스레딩(HT)과 물리적으로 밀집된 E코어 클러스터(Cluster 0)가 동시에 풀가동될 때 쿨링팬 소음 및 발열 스로틀링이 극심해집니다.
3. **충전기(AC) 및 배터리(DC) 전환 시 수동 설정의 번거로움**:
   - 배터리 사용 시에는 인텔 터보 부스트를 꺼서 배터리 수명을 대폭 확보하고, 충전기 연결 시에는 적절한 클럭 제한과 함께 성능을 내도록 자동 감지/전환 시스템이 필요합니다.

---

## 2. 적용되는 설정 및 시스템 경로

이 스크립트는 다음 위치에 설정 파일 및 도구들을 배치합니다:

| 대상 경로 | 설명 | 원본 파일 위치 |
| :--- | :--- | :--- |
| `/etc/sysctl.d/99-ssd-power-saving.conf` | SSD 더티 페이지 쓰기 주기 지연 및 laptop_mode 설정 | [`configs/sysctl/99-ssd-power-saving.conf`](./configs/sysctl/99-ssd-power-saving.conf) |
| `/etc/udev/rules.d/99-power-profile-switch.rules` | AC/DC 전원 어댑터 연결/분리 이벤트 감지 udev 룰 | [`configs/udev/99-power-profile-switch.rules`](./configs/udev/99-power-profile-switch.rules) |
| `/etc/sudoers.d/poweroptions` | 전원 스크립트 실행 시 비밀번호 입력을 면제하는 sudoers 설정 | [`configs/sudoers/poweroptions`](./configs/sudoers/poweroptions) |
| `~/bin/disable-ht.sh` | CPU 하이퍼스레딩 및 특정 E코어 토폴로지 제어 스크립트 | [`configs/bin/disable-ht.sh`](./configs/bin/disable-ht.sh) |
| `~/.config/autostart/` | 부팅 시 전원 프로필 및 CPU 토폴로지 자동 적용 데스크톱 항목 | [`configs/autostart/`](./configs/autostart/) |
| `~/Desktop/OneClickScripts/PowerOptions/` | 바탕화면에서 원클릭으로 전원/터보 모드를 변경하는 도구 모음 | [`configs/power_options/`](./configs/power_options/) |

---

## 3. 핵심 설정 파라미터 및 동작 원리

### (1) SSD 전력 소모 지연 (`/etc/sysctl.d/99-ssd-power-saving.conf`)
```ini
vm.dirty_writeback_centisecs = 6000
vm.dirty_expire_centisecs = 12000
vm.laptop_mode = 5
```
- writeback 주기를 기존 5초에서 60초(6000 centisecs)로 대폭 늘려 SSD의 불필요한 깨어남을 억제하고 NVMe 깊은 절전 모드를 유지합니다.

### (2) CPU 하이브리드 토폴로지 최적화 (`~/bin/disable-ht.sh`)
- **P코어 HT(보조 논리 스레드) 차단**: CPU 2, 4, 5, 7 비활성화 (싱글스레드 효율 극대화 및 발열 방지)
- **E코어 Cluster 0 차단**: 발열 밀집도가 높은 CPU 8~11 비활성화
- **E코어 Cluster 1 & LP-E코어 활성화**: 외곽 E코어(CPU 12~15) 및 초저전력 LP-E코어(CPU 16, 17)를 활성화하여 전력 대 성능비 최적화

### (3) AC/DC 자동 전환 시스템 (`/etc/udev/rules.d/99-power-profile-switch.rules`)
- 충전기(AC) 연결 시: 터보 부스트 ON (65% 클럭 제한 적용) + 균형 모드
- 배터리(DC) 전환 시: 터보 부스트 OFF (기본 클럭 100%) + 균형 모드 (발열 차단 및 배터리 타임 극대화)

---

## 4. 수동 확인 및 테스트 명령어

- **현재 CPU 코어 활성 상태 및 터보 상태 확인**:
  ```bash
  ~/Desktop/OneClickScripts/PowerOptions/check_status.sh
  ```
- **sysctl 커널 파라미터 확인**:
  ```bash
  sysctl vm.dirty_writeback_centisecs vm.laptop_mode
  ```

---

## 5. 롤백 (설정 원상 복구) 방법

```bash
# 1. sysctl 설정 제거
sudo rm -f /etc/sysctl.d/99-ssd-power-saving.conf
sudo sysctl --system

# 2. udev 룰 및 sudoers 제거
sudo rm -f /etc/udev/rules.d/99-power-profile-switch.rules
sudo rm -f /etc/sudoers.d/poweroptions
sudo udevadm control --reload

# 3. 자동 실행 및 스크립트 파일 제거
rm -f ~/.config/autostart/power-options-startup.desktop
rm -f ~/.config/autostart/disable-ht.desktop
rm -f ~/bin/disable-ht.sh
rm -rf ~/Desktop/OneClickScripts/PowerOptions

# 4. 모든 CPU 코어 다시 켜기
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    echo 1 | sudo tee "$cpu/online" 2>/dev/null || true
done
```
