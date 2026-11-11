# AXI bottleneck 검증

Vivado 2022.2의 `bin`을 PATH에 추가한 뒤 저장소 루트에서 실행합니다.

```powershell
.\scripts\behav_sim_axi.ps1
.\scripts\behav_sim_axi.ps1 -Seed 42
.\scripts\behav_sim_axi.ps1 -OutputFracBits 8
```

실행 스크립트는 ResNet-20 전체 추론을 검증합니다. 로그는 `build/sim/tb_axi_bottleneck/`에 생성됩니다.

최상위 TB에서 모델 패키지를 선택합니다. `resnet20/`에는 명령과 데이터, SV 더미, DPI-C float 연산기가 있습니다. kernel과 bias는 독립된 스트림으로 전송됩니다. 활성화된 DUT는 더미이며 실제 RTL 인스턴스 연결은 최상위 TB의 주석에 있습니다.

전체 추론은 최종 로짓 10개의 SNR이 50 dB 이상이면 통과합니다. 기준은 같은 Q5.10 입력·가중치로 계산한 양자화 전 Python float 로짓입니다. 입력과 기준 로짓은 `resnet20/data/`에 있으며, Python 3.10 이상에서 다음 명령으로 재생성할 수 있습니다.

`OUTPUT_FRAC_BITS`는 signed 16비트 최종 로짓에 적용하며 기본값은 10, 범위는 0~15입니다.

```powershell
python .\tb\tb_axi_bottleneck\resnet20\generate_fixture.py
```
