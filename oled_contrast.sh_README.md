# OLED 다크모드 대비 완화 및 Eye Care 패치 상세 설명서 (`oled_contrast.sh_README.md`)

이 문서는 갤럭시 북4 프로(Galaxy Book 4 Pro, NT960XGK / AMOLED) 등 OLED 패널 탑재 랩탑에서 다크모드 사용 시 눈부심을 줄이고 화면 잔상을 억제하기 위해 개발된 **OLED 대비 완화(화이트포인트 감소 & 리얼 블랙 회피) 패치**의 배경, 동작 원리, 설정 경로 및 관리 방법을 설명합니다.

---

## 1. 배경 및 목적

### 🔍 기존 환경에서의 문제점
1. **극단적인 명암비로 인한 야간 눈부심 및 눈 피로**:
   - OLED 패널의 순수 검은색(`0x000000`, 0 cd/m²) 배경 위에 최대 밝기의 순백색(`0xFFFFFF`) 글자나 아이콘이 표시될 때, 지나치게 높은 명암비(무한대 대비)로 인해 폰트 주변이 번져 보이거나 눈을 찌르는 듯한 피로감(Glare)이 발생합니다.
2. **OLED 리얼 블랙 스미어링 (True Black Smearing / 잔상 현상)**:
   - OLED 소자는 픽셀이 완전한 블랙(`0x000000`)일 때 전원을 완전히 차단(Off)합니다.
   - 스크롤을 하거나 창을 이동할 때 꺼져 있던 OLED 소자가 다시 켜지는 데 미세한 시간 지연이 발생하며, 이로 인해 검은색과 밝은색 경계면에서 보라색/암적색 잔상이 끌리는 **블랙 스미어링(Black Smearing)** 현상이 나타납니다.
3. **기존 색감 조정 시의 틴트(Tint) 왜곡 문제**:
   - 소프트웨어 밝기 조절이나 일반적인 CTM(Color Transform Matrix), TRC 커브 조작 방식은 OLED 패널의 비선형 감마 및 DCI-P3 광색역 특성과 충돌하여 무채색(회색조) 영역에 보라색이나 녹색 틴트가 끼는 심각한 색 왜곡을 유발했습니다.

### 🎯 패치의 목적
- 패널 고유의 EDID 색상 보정 정보는 100% 온전히 유지하면서, **하드웨어 16비트 VCGT(Video Card Gamma Table) LUT**를 주입하여:
  1. **블랙 리프트(+2.0% ~ +4.0%) 또는 리얼 블랙(0.0%)**: 취향에 따라 리얼 블랙을 미세하게 띄워(8비트 기준 약 `5`~`10`) 스미어링을 억제하거나, 0.0% 완전 소등으로 배터리/번인을 방어.
  2. **화이트포인트 감소(75.0% ~ 90.0%)**: 순백색 글자의 피크 광량을 안정적인 영역으로 낮추어(8비트 기준 약 `191`~`230`), 글자 가독성은 또렷하게 유지하면서 눈부심 원천 차단.
  3. **무왜곡 0% 틴트**: R, G, B 채널에 100% 동일한 선형 톤 램프 곡선을 주입하여 보라/녹색 틴트 왜곡이 일절 발생하지 않음.

---

## 2. 수정 및 생성되는 시스템 경로

| 구분 | 경로 | 설명 |
| :--- | :--- | :--- |
| **ICC 프로파일 (High Contrast)** | `~/.local/share/icc/oled_high_contrast.icc` | 화이트 90.0%, 블랙 +2.0% (기존 Gentle에서 개명, 균형형) |
| **ICC 프로파일 (High Pure Black)** | `~/.local/share/icc/oled_high_pure_black.icc` | 화이트 90.0%, 블랙 0.0% (밝은 화이트 + 리얼블랙 완전 소등) |
| **ICC 프로파일 (Medium Contrast)** | `~/.local/share/icc/oled_medium_contrast.icc` | 화이트 85.0%, 블랙 +4.0% (눈 편안함 최우선, 강한 대비 완화) |
| **ICC 프로파일 (Medium Pure Black)** | `~/.local/share/icc/oled_medium_pure_black.icc` | 화이트 85.0%, 블랙 0.0% (기존 Pure Black에서 개명, 전력/번인 최우선) |
| **ICC 프로파일 (Low Pure Black)** | `~/.local/share/icc/oled_low_pure_black.icc` | 화이트 75.0%, 블랙 0.0% (야간/암실 눈부심 극소화, 리얼블랙 완전 소등) |
| **커스텀 ICC 프로파일** | `~/.local/share/icc/oled_custom.icc` | `oled-mode custom` 실행 시 실시간 생성되는 프로파일 |
| **CLI 제어 도구** | `~/.local/bin/oled-mode` | 모드 전환, 실시간 튜닝, 원복을 수행하는 실행 스크립트 |
| **시스템 심볼릭 링크** | `/usr/local/bin/oled-mode` | 터미널 어디서나 `oled-mode`를 즉시 실행할 수 있는 링크 |
| **컬러 관리 데몬 등록** | `colord` DBus 서비스 | 시스템 및 GNOME 색상 관리자에 디스플레이 장치 프로파일로 등록 |

---

## 3. 주요 파라미터 및 원리

### ⚙️ VCGT (Video Card Gamma Table) 톤 램프 메커니즘
ICC 프로파일 내부의 `vcgt` 태그는 디스플레이 컨트롤러(GPU)의 출력 LUT에 직접 로드되는 16비트 감마 테이블입니다.

$$y = \text{black\_offset} + (\text{white\_max} - \text{black\_offset}) \times x$$

- $x \in [0.0, 1.0]$: 애플리케이션이 요청하는 정규화된 입력 밝기 (0: 순수 블랙, 1: 순수 화이트)
- $y \in [0.0, 1.0]$: 실제 디스플레이 패널로 출력되는 정규화된 16비트 LUT 출력값

### 📊 5종 프리셋 프로파일 상세 비교

화이트포인트 3단계(High 90% / Medium 85% / Low 75%)와 블랙 레벨(Contrast 리프트 / Pure Black 소등)의 조합으로 구성됩니다:

| 분류 | 프로파일 | 블랙 오프셋 | 화이트 상한선 | 8비트 환산 | 주요 용도 및 권장 환경 |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **High**<br>(화이트 90%) | **`High Contrast`** *(추천 기본값)*<br>`oled-mode high` | **`+2.0%`** | **`90.0%`** | `0` $\rightarrow$ `5`<br>`255` $\rightarrow$ `230` | **눈 + 전력 + 번인 최적 밸런스** (기존 Gentle).<br>OLED 특유의 깊은 블랙감을 유지하며 스미어링 완화 및 눈부심 차단 |
| | **`High Pure Black`**<br>`oled-mode high-pure` | **`0.0%`** | **`90.0%`** | `0` $\rightarrow$ `0`<br>`255` $\rightarrow$ `230` | **선명한 가독성 + 다크모드 배터리 절약**.<br>화이트를 90%로 적절히 낮추면서 리얼 블랙(0 cd/m²) 완전 소등 유지 |
| **Medium**<br>(화이트 85%) | **`Medium Contrast`**<br>`oled-mode medium` | **`+4.0%`** | **`85.0%`** | `0` $\rightarrow$ `10`<br>`255` $\rightarrow$ `217` | **눈의 편안함 & 스미어링 완전 제거 최우선**.<br>배경 소자가 4% 상시 발광하여 전력/번인 손해는 있으나 가장 부드러움 |
| | **`Medium Pure Black`**<br>`oled-mode medium-pure` | **`0.0%`** | **`85.0%`** | `0` $\rightarrow$ `0`<br>`255` $\rightarrow$ `217` | **전력 절약 & 번인 방지 최우선** (기존 Pure Black).<br>차분한 85% 화이트 + 리얼 블랙 완전 소등(0W)으로 번인/배터리 극대화 |
| **Low**<br>(화이트 75%) | **`Low Pure Black`**<br>`oled-mode low-pure` | **`0.0%`** | **`75.0%`** | `0` $\rightarrow$ `0`<br>`255` $\rightarrow$ `191` | **야간/암실 눈부심 극소화 + 배터리 절약**.<br>화이트를 75%로 대폭 낮춰 극저조도 환경에 최적화 + 리얼 블랙 완전 소등(0W) |
| **기타** | **`Custom`** | 사용자 지정 | 사용자 지정 | 자유 튜닝 | `oled-mode custom <블랙%> <화이트%>` 로 즉시 미세조정 |
| | **`Reset (순정)`** | `0.0%` | `100.0%` | `0` $\rightarrow$ `0`<br>`255` $\rightarrow$ `255` | 팩토리 기본값 복구 (100% 네이티브 광색역 출고 상태) |

### 🛠️ `oled-mode` CLI 명령어 사용법

```bash
# --- [화이트 90.0% 라인업 (High)] ---
# 1. High Contrast 적용 (화이트 90%, 블랙 +2.0% - 눈+전력 균형) [추천]
oled-mode high

# 2. High Pure Black 적용 (화이트 90%, 블랙 0.0% - 선명함 + 배터리 절약)
oled-mode high-pure

# --- [화이트 85.0% 라인업 (Medium)] ---
# 3. Medium Contrast 적용 (화이트 85%, 블랙 +4.0% - 눈 편안함 최우선)
oled-mode medium

# 4. Medium Pure Black 적용 (화이트 85%, 블랙 0.0% - 전력/번인 최우선)
oled-mode medium-pure

# --- [화이트 75.0% 라인업 (Low)] ---
# 5. Low Pure Black 적용 (화이트 75%, 블랙 0.0% - 야간/암실 눈부심 극소화)
oled-mode low-pure

# --- [기타 도구] ---
# 6. 실시간 커스텀 수치 생성 및 적용 (예: 블랙 2.0%, 화이트 92%)
oled-mode custom 2.0 92

# 7. 현재 적용 중인 컬러 프로파일 및 장치 확인
oled-mode status

# 8. 출고 순정 상태로 즉시 복원 (CTM 초기화 + 공장 EDID 프로파일 적용)
oled-mode reset
```

---

## 4. 사전 요구사항 및 의존성

- **운영체제**: Ubuntu 22.04 LTS / 24.04 LTS / 26.04+ (GNOME Wayland / X11 환경)
- **필수 패키지**:
  - `colord` (`colormgr`): 시스템 컬러 프로파일 관리 데몬
  - `liblcms2-2` (`liblcms2.so.2`): LittleCMS2 컬러 엔진 라이브러리 (ICC VCGT 태그 빌드용)
  - `python3-dbus`: Mutter `org.gnome.Mutter.DisplayConfig` CTM 제어용

> **참고**: `oled_contrast.sh` 실행 시 필수 패키지가 설치되어 있지 않으면 `apt`를 통해 자동으로 설치합니다.

---

## 5. 수동 확인 및 롤백 (원상 복구) 방법

### ✅ 수동 확인 방법
1. **CLI를 통한 현재 프로파일 확인**:
   ```bash
   oled-mode status
   ```
   출력 예시:
   ```text
   === 디스플레이 장치: xrandr-Samsung Display Corp.-0x4188-0x00000000 ===
     Title:         OLED Eye Care - High Contrast
     Filename:      /home/user/.local/share/icc/oled_high_contrast.icc
     Profile ID:    icc-7957dbba95c37895088c5ef3f803fbb6
   ```
2. **GUI 설정 앱 확인**:
   - 우분투 **설정(Settings) ➡️ 색상(Color)** 메뉴에서 내장 디스플레이(Built-in display)를 클릭하면 `OLED Eye Care - High Contrast` 프로파일이 등록되어 있는 것을 확인할 수 있습니다.

### 🔄 원상 복구 (원클릭 롤백)
언제든지 순정 상태로 되돌리려면 아래 명령을 실행합니다:

```bash
./oled_contrast.sh --restore
```

**롤백 스크립트의 동작 내용**:
1. `oled-mode reset`을 호출하여 패널 순정 공장 출하 EDID 프로파일로 전환 및 Mutter CTM 초기화
2. `colord` 디스플레이 장치 목록에서 등록된 OLED 맞춤 ICC 프로파일 5종 해제
3. `~/.local/share/icc/`에 설치된 맞춤 프로파일 파일 삭제
4. `~/.local/bin/oled-mode` 및 `/usr/local/bin/oled-mode` 파일 삭제
