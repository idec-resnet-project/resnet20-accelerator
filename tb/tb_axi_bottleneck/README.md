# AXI bottleneck 검증

Vivado 2022.2의 `bin`을 PATH에 추가한 뒤 저장소 루트에서 실행합니다.

```powershell
.\scripts\behav_sim_axi.ps1
.\scripts\behav_sim_axi.ps1 -Test model_inference_test -Seed 42
```

기본 실행은 단일 내적, 결과 오류 주입, 프로토콜 회귀, ResNet-20 전체 추론을 검증합니다. 로그는 `build/sim/tb_axi_bottleneck/`에 생성됩니다.

최상위 TB에서 모델 패키지를 선택합니다. `resnet20/`에는 명령과 데이터, SV 더미, DPI-C float 연산기가 있습니다. kernel과 bias는 독립된 스트림으로 전송됩니다. 활성화된 DUT는 더미이며 실제 RTL 인스턴스 연결은 최상위 TB의 주석에 있습니다.

입력과 독립 Python 기준 로짓은 `resnet20/data/`에 있습니다. Python 3.10 이상에서 다음 명령으로 재생성할 수 있습니다.

```powershell
python .\tb\tb_axi_bottleneck\resnet20\generate_fixture.py
```
