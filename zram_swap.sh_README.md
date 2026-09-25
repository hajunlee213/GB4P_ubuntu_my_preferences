# zram 압축 스왑 & SSD 수명 보호 (`zram_swap.sh`)

갤럭시 북4 프로(Galaxy Book 4 Pro, GB4P) 및 SSD 기반 노트북 환경에서 디스크 스왑 쓰기로 인한 NVMe SSD 마모(TBW 소모)를 방지하고, RAM 부족 시 발생하는 심각한 I/O 병목 및 시스템 프리징(Thrashing)을 차단하기 위해 **zram(압축 RAM 스왑)**을 구성하는 복원 스크립트입니다.

---

## 1. 배경 및 목적

우분투 기본 설치 환경에서는 루트 파일시스템 내에 4GB 크기의 단일 스왑 파일(`/swap.img`)을 디스크 기반으로 생성하여 사용합니다.

* **발생하는 문제점**:
  1. **SSD 수명 마모 (TBW 소모)**:
     - 스왑 활동이 발생할 때마다 NVMe SSD 낸드 플래시 메모리에 수 기가바이트의 빈번한 쓰기 작업이 가해져 SSD의 수명(Total Bytes Written, TBW)을 불필요하게 갉아먹습니다.
  2. **시스템 버벅임 및 프리징 (Swap Thrashing)**:
     - 램 사용량이 꽉 차서 스왑 파일로 페이지가 스왑아웃/스왑인될 때, RAM 대역폭(수십 GB/s)에 비해 현저히 느린 SSD I/O 병목 및 인터럽트 지연으로 인해 마우스 커서가 멈추거나 창 전환이 극도로 느려지는 스왑 쓰래싱이 발생합니다.
* **해결책**:
  - 최신 리눅스 표준인 `systemd-zram-generator`를 통해 물리 램(16GB)의 50%에 해당하는 **8GB 크기의 압축 가상 블록 디바이스(`/dev/zram0`)**를 생성합니다.
  - 최신 인텔 메테오레이크(Core Ultra 5 125H)의 뛰어난 멀티코어 연산력을 활용하여 **zstd** 실시간 압축 알고리즘으로 RAM 내부에서 데이터를 고속 압축/보관합니다.
  - zram의 스왑 우선순위를 `100`으로 높여 모든 스왑 트래픽을 초고속 RAM 영역으로 최우선 흡수하고, 기존 디스크 스왑(`/swap.img`, 우선순위 `-1`)은 zram이 완전히 고갈되었을 때만 개입하는 안전 후방 백업으로 유지합니다.

---

## 2. 수정 및 생성되는 시스템 경로

| 경로 | 역할 | 설명 |
| :--- | :--- | :--- |
| `configs/zram/zram-generator.conf` | 저장소 내 zram 설정 템플릿 | 8GB 크기, zstd 알고리즘, 우선순위 100 정의 |
| `/etc/systemd/zram-generator.conf` | 시스템 zram-generator 설정 파일 | 부팅 시 systemd가 zram 디바이스를 동적 생성하도록 지시 |
| `/dev/zram0` | 커널 가상 블록 디바이스 | RAM 내에 생성된 압축 스왑 파티션 장치 |
| `dev-zram0.swap` | systemd 스왑 마운트 유닛 | `/dev/zram0`을 스왑 영역으로 마운트 및 관리 |
| `systemd-zram-setup@zram0.service` | zram 초기화 서비스 | `/dev/zram0`의 디스크 크기 및 압축 알고리즘 초기화 |

---

## 3. 주요 파라미터 및 원리

### `/etc/systemd/zram-generator.conf` 설정값 분석

```ini
[zram0]
zram-size = 8192
compression-algorithm = zstd
swap-priority = 100
```

1. **`zram-size = 8192` (8GB)**:
   - 갤럭시 북4 프로 16GB RAM의 약 50%에 해당하는 8192MB 가상 스왑 디바이스를 생성합니다.
   - 평균 압축률 2~3배를 감안하면, 실제 약 2.5~3.5GB의 물리 RAM만 소모하면서도 최대 8GB에 이르는 비활성 메모리 데이터를 압축 수용하여 가용 메모리 확장 효과를 냅니다.
2. **`compression-algorithm = zstd`**:
   - 기존 `lzo`나 `lz4` 대비 압축률이 월등히 높아 한정된 RAM 공간을 극대화합니다.
   - 인텔 14코어 18스레드 메테오레이크 CPU 환경에서 멀티스레드 압축/해제 오버헤드가 극히 미미하여 지연 시간 없이 즉각 동작합니다.
3. **`swap-priority = 100`**:
   - 리눅스 커널의 스왑 우선순위 범위는 `-1`부터 `32767`까지입니다.
   - 우분투 기본 디스크 스왑(`/swap.img`)의 우선순위는 `-1`로 최하위입니다.
   - zram의 우선순위를 `100`으로 지정함으로써 커널 스왑 서브시스템은 **항상 zram0으로 먼저 스왑아웃**하며, 8GB zram이 100% 가득 찬 극한의 상황에서만 NVMe 스왑 파일(`/swap.img`)을 fallback(후방 지원)으로 사용합니다.

---

## 4. 사전 요구사항 및 의존성

* **운영체제**: Ubuntu 22.04 LTS / 24.04 LTS / 26.04 LTS
* **필수 패키지**: `systemd-zram-generator` (APT 기본 저장소 제공)
* **커널 모듈**: `zram` (우분투 공식 커널 기본 내장)
* **실행 권한**: root 권한 (`sudo`)

---

## 5. 실행 방법

### zram 압축 스왑 복원 적용
```bash
sudo ./zram_swap.sh
```
*(일반 사용자로 실행 시 자동으로 sudo 권한 승격을 요청합니다)*

---

## 6. 수동 확인 및 롤백 (원상 복구) 방법

### 적용 상태 확인

1. **zram 디바이스 및 압축 상태 확인**:
   ```bash
   zramctl
   ```
   * 정상 출력 예시:
     ```text
     NAME       ALGORITHM DISKSIZE DATA COMPR TOTAL STREAMS MOUNTPOINT
     /dev/zram0 zstd            8G  ...   ...   ...       ... [SWAP]
     ```

2. **전체 스왑 우선순위 계층 확인**:
   ```bash
   swapon --show
   ```
   * 정상 출력 예시:
     ```text
     NAME       TYPE      SIZE USED PRIO
     /dev/zram0 partition   8G   0B  100
     /swap.img  file        4G  ...   -1
     ```

### 원클릭 순정 롤백

```bash
sudo ./zram_swap.sh --restore
```
또는
```bash
sudo bash scripts/restore-zram-swap.sh
```

### 수동 롤백 단계 (스크립트 미사용 시)

1. zram 스왑 즉시 비활성화:
   ```bash
   sudo swapoff /dev/zram0
   ```
2. 관련 systemd 서비스 중지 및 설정 파일 삭제:
   ```bash
   sudo systemctl stop dev-zram0.swap systemd-zram-setup@zram0.service
   sudo rm -f /etc/systemd/zram-generator.conf
   sudo systemctl daemon-reload
   ```
3. zram 블록 디바이스 리셋 및 패키지 삭제:
   ```bash
   sudo zramctl --reset /dev/zram0
   sudo apt-get remove -y systemd-zram-generator
   ```
4. 디스크 스왑 상태 확인:
   ```bash
   swapon --show
   ```
   (`/swap.img`만 활성화된 순정 상태로 복구됨)
