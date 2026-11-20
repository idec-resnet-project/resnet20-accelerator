# conv_top / packed module testbenches

`conv_top` 을 구성하는 packed 모듈 4개를 각각 단독으로 검증하는 테스트벤치와,
`conv_top` 전체를 검증하는 테스트벤치(`tb_conv_top.v`)입니다. 모두 self-checking 입니다.
**같은 TB 파일로 behavioral simulation 과 post-implementation timing simulation 을 모두** 돌릴 수 있고,
클럭 주파수는 parameter 하나(`CLK_FREQ_MHZ`)로 바꿉니다. 기본값은 100 MHz 입니다.
`conv_top` TB 는 아래 [conv_top 테스트벤치](#conv_top-테스트벤치) 섹션을 참고하세요.

## 파일 구성

| TB | DUT | 입력 포트 | 출력 포트 |
|---|---|---|---|
| `tb_mac_packed.v` | `mac_packed` | `clk`, `rst_n`, `enable`, `valid_in`, `iter[15:0]`, `fmap_in[15:0]`, `weight_in[15:0]` | `valid_out`, `data_out[15:0]` |
| `tb_ReLU_packed.v` | `ReLU_packed` | `clk`, `rst_n`, `enable`, `valid_in`, `data_in[15:0]` | `valid_out`, `data_out[15:0]` |
| `tb_residual_packed.v` | `residual_packed` | `clk`, `rst_n`, `enable`, `valid_in`, `data_in[15:0]`, `data_skip[15:0]` | `valid_out`, `data_out[15:0]` |
| `tb_pooling_packed.v` | `pooling_packed` | `clk`, `rst_n`, `enable_avg`, `enable_max`, `valid_in`, `max_iter[15:0]`, `avg_iter[15:0]`, `data_in[15:0]` | `valid_out`, `data_out[15:0]` |
| `tb_conv_top.v` | `conv_top_wrapper` (기본) / `conv_top` (`NO_WRAPPER`) | `clk`, `nrst`, `mac_enable`, `mac_iteration[15:0]`, `residual_enable`, `relu_enable`, `pooling_enable`, `pooling_iteration[15:0]`, `gap_enable`, `gap_iteration[15:0]`, `in_enable`, `in_data[15:0]`, `kernel_data[15:0]`, `bias_data[15:0]` | `out_enable`, `out_data[15:0]` |

- 데이터 포트는 모두 16b signed Q7.8, 리셋(`rst_n`, `nrst`)은 active-low 입니다.
- TB 는 DUT 에 parameter 를 넘기지 않으므로, 위 폭이 DUT parameter 기본값이어야 합니다.
- 보조 파일: `conv_top_wrapper.v` (conv_top 입출력 IOB 레지스터 + reset 동기화 + reset 중 loopback),
  `tb_packed_io.xdc` / `tb_conv_io.xdc` (post-implementation 용 클럭 / 입력 타이밍 제약)

> `post_mac_lhs.v` 와 `post_mac_pipe4.v` 는 모듈 이름(`post_mac`)이 같으므로 **둘 중 하나만** 프로젝트에 넣으세요.
> TB 는 latency 를 직접 측정하기 때문에 어느 쪽을 써도 그대로 동작합니다 (pipe4 는 latency +1).

## 판정 기준 / 콘솔 출력

모든 결과는 `$display` 로 **Vivado Tcl 콘솔**에 출력됩니다.

- **PASS / FAIL**
  `valid_out == 1` 인 사이클의 `data_out` 을 샘플해서 고정소수점(Q7.8) 기준 모델과 **bit-exact** 비교합니다.
  출력 개수 불일치, 값 불일치, 출력의 X/Z 가 하나라도 있으면 FAIL 입니다.
- **bypass 케이스** (`enable = 0`)
  `valid_out` 이 한 번도 뜨지 않아야 하고, `data_out` 이 `data_in` 을 그대로 통과시켜야 PASS 입니다.
- **SNR**
  `SNR(dB) = 10·log10( Σref² / Σ(dut − ref)² )`, ref 는 반올림/절삭이 없는 실수 모델입니다.
  오차가 0 이면 `INF` 로 표시하고 평균에서 제외합니다. 케이스별 SNR 과 평균 / 최소 / 최대 SNR 을 출력합니다.
- **LATENCY**
  `valid_in`(= `conv_top` 의 `in_enable`) 이 내려간 뒤 `valid_out` 이 1 이 될 때까지 지난 **posedge 수**입니다.
  즉 *마지막 입력을 캡처한 posedge* 부터 *`valid_out` 을 올린 posedge* 까지의 차이입니다.
  `EN_MODE = 1` 이면 `enable` 도 `valid_in` 과 같이 내려가므로 "enable 하강 기준"과 같은 값입니다.
  back-to-back 스트림에서도 토큰마다 같은 기준으로 계산하고, 케이스별 값과 전체 평균을 출력합니다.

### 출력 형식

```
[CAL] clk->data_out : min  0.000 ns / max  0.000 ns  (behavioral = 0 / 0)
[CAL] output sample : launch edge +  5.000 ns  (posedge +  5.000 ns, k=0)
------------------------------------------------------------------------
[CASE  3] [MAC] iter=9 (3x3 kernel)
  config  : enable=1  iter=9  windows=32  gap=4
  outputs : expected=32  received=32  mismatches=0
  LATENCY : 7 clk  (posedges after valid_in(enable) falls)
  SNR     :    xx.xx dB
  RESULT  : PASS
...
====================================================================================================
  mac_packed TEST SUMMARY   (CLK 100.000 MHz = 10.000 ns, IN_DLY 6.000 ns, EN_MODE 0)
====================================================================================================
  No | Result |  Exp |  Got |  Err |  Lat(clk) |  SNR(dB)  | Case
 ----+--------+------+------+------+-----------+-----------+------------------------------------------
   1 |  PASS  |   32 |   32 |    0 |         7 |     xx.xx | [MAC] iter=1
 ...
  TOTAL           : n / n PASS  (0 FAIL)
  AVERAGE SNR     :    xx.xx dB   (finite cases = n, INF cases = n excluded)
  SNR MIN / MAX   :    xx.xx dB /    xx.xx dB
  AVERAGE LATENCY :     x.xx clk  (min x / max x, cases = n)
```

## Behavioral simulation (Vivado GUI)

1. RTL 파일과 TB 파일을 프로젝트에 추가합니다 (TB 는 *Simulation Sources*).
2. *Simulation Sources* 에서 돌릴 TB 를 우클릭 → **Set as Top**.
3. **Run Simulation → Run Behavioral Simulation**.
4. 기본 run time(1000 ns)으로는 끝나지 않으므로 Tcl 콘솔에서 `run all`.
   (매번 치기 싫으면 Simulation Settings → Simulation 탭 → `xsim.simulate.runtime` 을 `all` 로 설정)

Tcl 로 하면:

```tcl
set_property top tb_mac_packed [get_filesets sim_1]
launch_simulation
run all
```

## Post-implementation timing simulation

TB 는 DUT 를 **parameter override 없이** 인스턴스하므로 timing netlist 에도 그대로 붙습니다.
모듈마다 그 모듈을 top 으로 implementation 해야 합니다.

1. `tb_packed_io.xdc` 를 constraint 로 추가합니다.
   (`conv_top` 용 XDC 와 섞이지 않게 별도 constraint set 을 만들어 활성화하는 것을 권장)
2. *Design Sources* 에서 검증할 packed 모듈(예: `mac_packed`)을 **Set as Top** → **Run Implementation**.
3. `report_timing_summary` 에서 입력 경로의 setup / hold 위반이 없는지 확인합니다.
4. *Simulation Sources* 에서 해당 TB 를 Top 으로 → **Run Simulation → Run Post-Implementation Timing Simulation** → `run all`.

```tcl
set_property top mac_packed    [current_fileset]
set_property top tb_mac_packed [get_filesets sim_1]
reset_run synth_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
launch_simulation -mode post-implementation -type timing
run all
```

### timing sim 에서 입출력 시점 처리

- **입력**: posedge 후 `IN_DLY = IN_DLY_RATIO × 주기` 에 바꿉니다 (기본 0.6 → 100 MHz 에서 6 ns).
  XDC 의 input delay 를 같은 값으로 주면 Vivado 가 그 시점 기준으로 setup / hold 를 맞춥니다.
- **출력**: 시뮬레이션 시작 시 bypass 경로(`data_out <= data_in`)로 clk→out 지연을 자동 측정하고
  (`[CAL]` 로그), 출력이 안정된 구간의 가운데 시점에서 샘플합니다.
  그래서 clk→out 이 한 주기를 넘어도 latency 는 behavioral 과 같은 기준(클럭 수)으로 나옵니다.
  behavioral 에서는 지연이 0 이므로 `[CAL] min 0 / max 0` 으로 표시됩니다.
- 시작 후 200 ns 동안은 대기합니다 (Xilinx GSR 100 ns 이후 시작).

## 주파수 변경

주파수는 TB 의 `CLK_FREQ_MHZ` parameter (단위 MHz, real) 로 정합니다. 주기와 입력 인가 시점은 자동으로 계산됩니다.

```verilog
parameter real CLK_FREQ_MHZ = 100.0;   // 클럭 주파수 [MHz]
parameter real IN_DLY_RATIO = 0.6;     // 입력 인가 시점 = posedge 후 (IN_DLY_RATIO x 주기)
// CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ,  IN_DLY = CLK_PERIOD * IN_DLY_RATIO
```

바꾸는 방법은 아래 중 하나를 쓰면 됩니다.

**1. TB 파일의 기본값 수정** — 가장 간단합니다.

```verilog
parameter real CLK_FREQ_MHZ = 50.0;
```

**2. Vivado GUI** — 파일을 고치지 않고 바꿀 때
Flow Navigator → *Simulation* 우클릭 → **Simulation Settings** → *Compilation* 탭 →
**Generics/Parameters options** 에 `CLK_FREQ_MHZ` = `50.0` 추가.

**3. Vivado Tcl 콘솔** — elaboration 옵션으로 top parameter 를 덮어씁니다.

```tcl
set_property -name {xsim.elaborate.xelab.more_options} \
             -value {-generic_top "CLK_FREQ_MHZ=50.0"} \
             -objects [get_filesets sim_1]
```

여러 개를 바꿀 때는 `-generic_top` 을 반복합니다.

```tcl
set_property -name {xsim.elaborate.xelab.more_options} \
             -value {-generic_top "CLK_FREQ_MHZ=50.0" -generic_top "IN_DLY_RATIO=0.5"} \
             -objects [get_filesets sim_1]
```

**4. xsim 커맨드라인 (standalone)**

```sh
xvlog tb_mac_packed.v mac_packed_lhs.v mac_v3_lhs.v post_mac_lhs.v mux_lhs.v
xelab tb_mac_packed -generic_top "CLK_FREQ_MHZ=50.0" -s tb_mac_sim
xsim  tb_mac_sim -R
```

> **post-implementation timing sim 에서 주파수를 바꿀 때는 `tb_packed_io.xdc` 도 같이 바꾸고 implementation 을 다시 돌려야 합니다.**
>
> | CLK_FREQ_MHZ | create_clock -period | set_input_delay (0.6 × T) |
> |---|---|---|
> | 50 | 20.000 | 12.000 |
> | 100 | 10.000 | 6.000 |
> | 125 | 8.000 | 4.800 |
> | 150 | 6.667 | 4.000 |
> | 200 | 5.000 | 3.000 |
>
> 목표 주파수에서 implementation 이 timing 을 못 맞추면 timing sim 에서 X 가 나오거나 FAIL 이 날 수 있습니다.
> 콘솔 맨 위 `tb_xxx (... CLK xxx MHz = xx ns, IN_DLY xx ns ...)` 줄에서 실제 적용된 값을 확인할 수 있습니다.

## Parameters

| parameter | 기본값 | 설명 |
|---|---|---|
| `CLK_FREQ_MHZ` | `100.0` | 클럭 주파수 [MHz] |
| `IN_DLY_RATIO` | `0.6` | 입력 인가 시점 = posedge 후 `IN_DLY_RATIO × 주기` (0 < 값 < 1). timing sim 에서 XDC input delay 와 맞출 것 |
| `EN_MODE` | `0` | `0`: 케이스 동안 `enable` 고정 (conv_top 방식) / `1`: `enable` 이 `valid_in` 과 같이 오르내림 |
| `REF_CLIP` | `1` | SNR 기준 모델 — `1`: Q7.8 범위로 clip / `0`: clip 없음 (포화 오차도 SNR 에 반영) |
| `SEED` | `1` | 랜덤 시드 |

## 테스트 케이스

모든 TB 는 시작 시 calibration 후 케이스마다 reset → 입력 → 결과 출력 순서로 진행하고, 마지막에 요약표를 출력합니다.
`valid_in = 0` 인 사이클에는 데이터 버스에 랜덤 값(garbage)을 넣어서, 무효 구간의 데이터가 결과에 섞이지 않는지도 함께 확인합니다.

**`tb_mac_packed`**
iter = 1 / 3 / 9 / 16 / 25 / 64, iter = 0 (출력 0), 윈도우마다 iter 가 바뀌는 mixed (시작 외 시점에 iter 포트 garbage),
윈도우 간 최소 간격(idle 3 clk), single-shot(idle 12 clk), 반올림 경계, ± 포화(full-scale), full-range 랜덤(iter = 7),
all-zero, weight = 1.0 identity, bypass

**`tb_ReLU_packed`**
full-range back-to-back, 랜덤 bubble, single-shot, 작은 범위(±2.0), 전부 양수, 전부 음수, 경계값, 부호 교대,
긴 스트림(1024), bypass

**`tb_residual_packed`**
작은 범위 랜덤, full-range(포화 빈번), 랜덤 bubble, single-shot, 고정 skip(+300 / −500, conv_top bias 방식),
skip = 0, + 포화 경계, − 포화 경계, skip = +32767 / −32768, 긴 스트림(1024), bypass

**`tb_pooling_packed`**
MAX: K = 2 / 4 / 9 / 1, 최소 간격(idle 1 clk), 윈도우 내부 bubble, mixed K(1~9), 음수 / 동일값 / 극값
GAP: K = 2 / 4 / 8 / 16 / 64 / 128 / 1, 최소 간격, 윈도우 내부 bubble, mixed K(2ⁿ), 작은 범위, 음수 floor, full-scale
MAX + GAP 동시 enable (avg 우선), bypass

## 다른 RTL 로 교체해서 테스트하기

같은 기능을 하는 다른 구현으로 바꿔도 **TB 수정 없이** 그대로 테스트할 수 있습니다.
위 *파일 구성* 표의 RTL 대신 새 구현 파일을 넣고 같은 방법으로 돌리면 됩니다.

- TB 는 DUT 의 **포트만** 사용하고, 내부 신호나 하위 모듈 이름은 참조하지 않습니다.
- latency 를 고정값으로 기대하지 않고 **매번 측정**하므로 파이프라인 단수가 달라도 됩니다.
  (예: `post_mac_lhs.v` → `post_mac_pipe4.v` 로 바꾸면 latency 만 +1 되고 판정은 그대로 PASS)
- bypass pass-through 지연도 0 ~ 3 클럭 중에서 자동으로 찾습니다.

### 반드시 맞춰야 하는 것

| 항목 | 조건 | 어긋나면 |
|---|---|---|
| 모듈 이름 / 포트 | 이름·포트명·폭이 같아야 함 (데이터 16b, iter 16b). TB 가 parameter 를 넘기지 않으므로 (post-impl netlist 호환) **parameter 기본값도 이 폭**이어야 함 | 컴파일 / elaboration 에러 |
| 리셋 | `rst_n` active-low, 4 클럭 안에 리셋 완료 (동기 / 비동기 무관) | 첫 케이스부터 FAIL |
| `valid_out` | 결과 1개당 **정확히 1클럭 펄스**, 입력 순서대로 출력 | 2클럭 이상 유지하면 출력 개수 초과로 FAIL |
| 수치 규칙 | MAC: `+127 / +128` 후 `>>> 8` 반올림 + int16 포화 · GAP: floor (`>>>`) · residual: int16 포화 | 값 불일치로 FAIL (SNR 은 정상 출력되므로 정확도 비교용으로는 사용 가능) |

### 현재 RTL 의 동작 방식에 맞춰진 케이스

아래 동작이 다른 RTL 이면 **해당 케이스만** FAIL 이 납니다. 기능 오류가 아니라 동작 방식 차이일 수 있으니 케이스 이름으로 구분하세요.

| 항목 | TB 가 가정하는 동작 | 관련 케이스 |
|---|---|---|
| MAC 입력 방식 | 첫 입력(`enable && valid_in`)부터 `iter` 개를 연속 입력, 윈도우 사이 idle 기본 4 클럭 (최소 간격 케이스는 3 클럭) | 모든 MAC 케이스, `[MAC] iter=9, min gap` |
| MAC iter = 0 | 입력 1개를 받고 0 을 출력 | `[MAC] iter=0 (expect 0)`, `[MAC] mixed iter ...` |
| iter / K 래치 | `iter`, `max_iter`, `avg_iter` 는 첫 입력 때만 래치 (나머지 시점엔 포트에 garbage 를 넣음) | `[MAC] mixed iter ...`, `[MAX] mixed K ...`, `[GAP] mixed K ...` |
| ReLU / residual 입력 | 매 클럭 입력 가능 (back-to-back), 입력 사이 bubble 허용 | back-to-back / bubble / long stream 케이스 |
| pooling 윈도우 내부 bubble | 윈도우 중간에 `valid_in = 0` 이 끼어도 계속 누적 | `[MAX] / [GAP] ... bubble inside window` |
| pooling 윈도우 간격 | 윈도우 사이 최소 idle 1 클럭 (기본 2 클럭) | 모든 pooling 케이스, `... min gap (1 idle clk)` |
| MAX + GAP 동시 enable | avg 결과가 출력됨 | `[MAX+GAP] both enabled (avg wins)` |
| bypass (`enable = 0`) | `valid_out` 이 뜨지 않고, data 만 레지스터 한 단을 거쳐 통과 | `... bypass` 케이스 |

`avgpool` 은 K 가 2ⁿ (≤ 128) 일 때만 나눗셈(`sum >>> log2 K`, floor)을 하므로 GAP 케이스는 2ⁿ 만 사용합니다.
새 구현이 임의의 K 를 지원해도 결과에는 영향이 없습니다.

### post-implementation timing sim 주의

TB 는 시작할 때 bypass pass-through(`enable = 0` 에서 `data_out <= data_in`, MAC 은 `fmap_in`)로 출력 지연(clk→out)을 측정합니다.
새 RTL 이 bypass 에서 data 를 통과시키지 않으면 `[CAL] WARNING` 이 뜨고 샘플 시점을 T/2 로 둡니다.
post-impl 에서는 clk→out 이 보통 T/2 보다 커서 latency 가 1 클럭 어긋나거나 값이 틀릴 수 있으니, 이 경우에는 결과를 따로 확인해야 합니다.
behavioral sim 은 영향이 없습니다.

---

## conv_top 테스트벤치

`tb_conv_top.v` 는 `conv_top` 전체(MAC → residual → ReLU → pooling, ResNet 의 conv → add → ReLU 순서)를 검증합니다.
판정 / SNR / 출력 형식은 packed TB 와 같고, 블록 enable 조합별 케이스를 돌립니다.

### DUT 선택 (Verilog define)

| define | 동작 |
|---|---|
| (없음, 기본) | DUT = `conv_top_wrapper`, 그 안의 core = `conv_top` |
| `NO_WRAPPER` | wrapper 없이 core 를 직접 DUT 로 사용 (behavioral 전용, 출력 타이밍 보정 없음) |
| `CORE_MODULE=<이름>` | core 모듈 이름 변경 (예: `CORE_MODULE=conv_top_v2`). wrapper 와 TB 둘 다 적용 |
| `WRAPPER_PASS_PARAMS` | wrapper 가 core 에 parameter 를 이름으로 넘김 (기본은 넘기지 않음) |

define 설정 방법:

- **GUI**: Simulation Settings → *Compilation* 탭 → **Verilog options** 에서 define 추가
- **Tcl**:
  ```tcl
  set_property verilog_define {CORE_MODULE=conv_top_v2} [get_filesets sim_1]
  ```
- **post-implementation** 용으로 wrapper 를 합성할 때는 synthesis 쪽(`sources_1`)에도 같은 define 을 넣어야 합니다.
  ```tcl
  set_property verilog_define {CORE_MODULE=conv_top_v2} [get_filesets sources_1]
  ```

### Parameters

| parameter | 기본값 | 설명 |
|---|---|---|
| `CLK_FREQ_MHZ` | `100.0` | 클럭 주파수 [MHz] (변경 방법은 [주파수 변경](#주파수-변경) 과 동일) |
| `IN_DLY_RATIO` | `0.75` | 입력 인가 시점 = posedge 후 `IN_DLY_RATIO × 주기`. wrapper IOB 입력 기준 (100 MHz 에서 7.5 ns) |
| `MAC_GAP` | `4` | MAC 윈도우 사이 idle 클럭 (현재 RTL 최소 3) |
| `POOL_GAP` | `2` | pooling 윈도우 사이 idle 클럭 (현재 RTL 최소 1) |
| `RST_WAIT` | `8` | `nrst` 해제 후 첫 입력까지 대기 클럭 (wrapper 동기화 2 + core 내부 리셋 지연 포함) |
| `REF_CLIP` | `1` | SNR 기준 모델 — `1`: Q7.8 범위로 clip / `0`: clip 없음 |
| `SEED` | `1` | 랜덤 시드 |

### LATENCY

`in_enable` 이 내려간 뒤 `out_enable` 이 1 이 될 때까지 지난 posedge 수입니다.
출력 1개를 만드는 **마지막 입력**(MAC 이면 윈도우의 마지막 곱, pooling 이면 K 번째 토큰의 마지막 입력)을 캡처한 posedge 기준으로 출력마다 계산하고,
**wrapper 의 입출력 레지스터 +2 클럭은 빼고 core 기준**으로 표시합니다. 그래서 `NO_WRAPPER` 로 돌려도 같은 값이 나옵니다.

### 출력 타이밍 보정 (wrapper)

wrapper 는 리셋 중(`nrst = 0`)에 `out_data` 로 `in_data` 를 2 클럭 늦게 내보냅니다 (입력 IOB FF → 출력 IOB FF).
TB 는 시작할 때 이 경로로 clk→out 지연을 측정해서(`[CAL]` 로그) 출력이 안정된 구간의 가운데에서 샘플합니다.
core RTL 과 무관한 경로라서 core 를 바꿔도 그대로 동작하고, 리셋 중 `out_enable` 은 0 이므로 기능에는 영향이 없습니다.

### wrapper 를 다른 RTL 에 쓸 때

`conv_top_wrapper.v` 는 core 의 **포트에만** 연결하므로, `conv_top` 과 같은 포트를 가진 RTL 이면 그대로 쓸 수 있습니다.

- core 모듈 이름이 `conv_top` 이 아니면 `CORE_MODULE=<이름>` define 을 줍니다 (post-impl 합성 시 `sources_1` 에도).
- core 에 parameter 를 넘기지 않으므로 core 의 parameter 기본값이 데이터 16b / iteration 16b / `PARALLEL_PC = 1` 이어야 합니다.
  이름이 같으면 `WRAPPER_PASS_PARAMS` 로 값을 넘길 수 있습니다.
- core 에는 wrapper 안에서 동기화된 `nrst` (active-low) 가 들어갑니다. core 내부의 동기 / 비동기 리셋 방식은 상관없습니다.
- 입력 / 출력을 한 단씩 등록하므로 core 대비 **latency +2 클럭**입니다 (`tb_conv_top` 은 이 2 클럭을 빼고 표시).
- 리셋 중에는 `out_data` 로 `in_data` 가 나옵니다 (출력 타이밍 보정용, 리셋 중 `out_enable` = 0).
- 데이터 레지스터(`in_data`, `kernel_data`, `bias_data`, `out_data`)에는 리셋이 없고, enable / config / valid 레지스터만 리셋됩니다.
- 포트 구성이 다른 RTL 에는 그대로 쓸 수 없습니다. 이 경우 wrapper 의 포트 선언과 입출력 레지스터 부분을 그 RTL 포트에 맞게 고쳐야 합니다.

### post-implementation timing sim

1. `tb_conv_io.xdc` 를 constraint 로 추가합니다.
2. *Design Sources* 에서 `conv_top_wrapper` 를 **Set as Top** → **Run Implementation**.
3. *Simulation Sources* 에서 `tb_conv_top` 을 Top 으로 → **Run Post-Implementation Timing Simulation** → `run all`.

```tcl
set_property top conv_top_wrapper [current_fileset]
set_property top tb_conv_top      [get_filesets sim_1]
reset_run synth_1
launch_runs impl_1 -jobs 4
wait_on_run impl_1
launch_simulation -mode post-implementation -type timing
run all
```

### 다른 RTL 로 교체해서 테스트하기

TB 와 wrapper 는 core 의 **포트만** 사용하고 parameter 도 넘기지 않으므로, 같은 포트를 가진 다른 구현을 그대로 넣을 수 있습니다.
기대값은 RTL 구조를 흉내 낸 것이 아니라 **conv_top 이 계산해야 하는 기능 모델**입니다.

- 모듈 이름이 `conv_top` 이면 파일만 바꿔 넣으면 되고, 이름이 다르면 `CORE_MODULE` define 을 줍니다.

**반드시 맞춰야 하는 것**

| 항목 | 조건 |
|---|---|
| 포트 | `conv_top` 과 같은 포트 이름 / 폭 (데이터 16b, iteration 16b, `PARALLEL_PC = 1`). parameter 기본값도 이 폭이어야 함 |
| 리셋 | `nrst` active-low, 해제 후 `RST_WAIT` 클럭 안에 입력을 받을 수 있어야 함 |
| `out_enable` | 결과 1개당 정확히 1클럭 펄스, 입력 순서대로 출력 |
| 수치 규칙 | MAC: `+127 / +128` 후 `>>> 8` 반올림 + int16 포화 · residual: int16 포화 · GAP: floor (`>>>`) |
| 블록 bypass | enable 이 0 인 블록은 값을 바꾸지 않고 통과시키며, **valid 와 data 가 같은 클럭에 맞춰져** 다음 블록으로 가야 함 |

**동작 방식에 따라 조정할 수 있는 것**

| 항목 | TB 가정 | 다르면 |
|---|---|---|
| MAC 입력 방식 | 첫 입력부터 iter 개를 연속 입력, 윈도우 사이 idle `MAC_GAP` 클럭 | `MAC_GAP` 조정 |
| pooling 윈도우 간격 | 윈도우 사이 idle `POOL_GAP` 클럭, MAC 출력 간격만큼 윈도우 내부 bubble 허용 | `POOL_GAP` 조정 |
| MAC iter = 0 | 입력 1개를 받고 0 출력 | `[C] MAC iter=0` 케이스만 FAIL |
| MAX + GAP 동시 enable | avg 결과 | `[C] MAX+GAP both enabled` 케이스만 FAIL |
| GAP K | 2ⁿ (≤ 128) 만 사용 | 영향 없음 |

### 테스트 케이스

블록 0개(bypass), 1개(MAC / ReLU / RES / MAXPOOL / GAP), 2개 · 3개 조합 전부, 4개(MAC + RES + ReLU + MAX | GAP),
코너 케이스(MAC 반올림 경계, iter = 0, iter = 16, ± 포화, full-range, all-zero, ReLU 경계값, residual ± 포화,
MAXPOOL / GAP iter = 1, MAXPOOL 음수 / 극값, GAP 음수 floor, GAP full-scale, MAX + GAP 동시, 긴 back-to-back 스트림).