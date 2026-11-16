# TB 실행 규칙

저장소 루트에서 Windows 명령 프롬프트로 실행합니다.

```bat
scripts\behav_sim.bat tb_axi_bottleneck_partial --no-wdb
scripts\behav_sim.bat tb_axi_bottleneck_toy --no-wdb
```

| 옵션 | 동작 |
|---|---|
| `--no-wdb` | WDB 저장 생략 |
| `--gui` | 완료 후 저장된 파형 열기 |
| `--gui-live` | 라이브 파형 창에서 실행 |
| `--skip-compile` | 기존 스냅샷 재사용. 소스·DUT·파일 목록 변경 후에는 새로 컴파일 |

## 폴더와 파일 목록

```text
tb/
  libs/                         # 선택적인 공용 include 경로
    interfaces/
    model_contract_pkg.sv
    uvm/
    rtl/
    models/
      resnet20/data/
      resnet20_partial/data/
      toy/data/
  <tb_name>/
    <tb_name>.sv                 # top module 이름도 동일
    <tb_name>.f
    <tb_name>.wcfg               # 선택
    wave_setup.tcl              # 선택
    include/                    # 선택
```

`.f`에는 TB 폴더 기준 소스 경로를 한 줄에 하나씩 컴파일 순서대로 적습니다. 빈 줄과 `#`, `//`로 시작하는 주석을 허용합니다. 공백을 포함한 경로도 따옴표 없이 한 줄에 적습니다. `.v`, `.sv`는 HDL 컴파일 대상으로, `.c`는 DPI 컴파일 대상으로 처리합니다. 파일 목록에는 셸 명령이나 도구 옵션을 넣지 않습니다.

실행기는 `xvlog`와 `xelab`에 항상 `-L uvm`을 전달합니다. 일반 SV TB도 사용할 수 있습니다. TB 폴더, 존재하는 `include/`와 `tb/libs/`, HDL 소스의 디렉터리를 include 검색 경로에 추가합니다. `libs`가 없어도 실행할 수 있습니다.

모든 TB에 `TB_DIR` plusarg로 TB의 절대 경로를 전달합니다. 모델 패키지의 `model_data_dir(tb_dir)`로 사전 생성 데이터 경로를 얻습니다. 실행 중 작업 디렉터리는 `.log/sim/<tb_name>`입니다. 데이터가 누락되면 모델 로더가 파일 경로와 함께 실패를 보고합니다.

새 TB도 `.f`와 같은 이름의 top으로 실행할 수 있습니다. 검증 완료 후 오류가 없을 때 정확히 `[ PASS ] ALL TESTS PASSED`를 한 줄로 출력해야 합니다. 실행기는 도구 종료 코드, fatal/error와 UVM 오류 집계, 이 성공 문구를 검사합니다. 공용 UVM 테스트는 final phase에서 성공을 출력합니다.

## 모델과 DUT 선택

`.f`에서 `resnet20`, `resnet20_partial`, `toy`의 `model_pkg.sv` 중 하나를 선택합니다. 공통 진입점은 `build_model_config(data_dir, output_frac_bits)`입니다. UVM은 top이 전달한 설정으로 명령과 데이터를 보내고 결과를 검사합니다.

각 AXI top의 DUT 인스턴스 한 곳에서 `axi_bottleneck` 또는 주석으로 제공된 `axi_bottleneck_dummy`를 선택합니다. 더미 DUT는 backend 초기화와 해제를 내부에서 처리합니다. `.f`에 포함된 `model_backend_pkg.sv`와 `model_compute.c`가 DPI 연산을 제공합니다. C 파일이 목록에 있으면 RTL 선택 시에도 C 컴파일을 수행합니다. DUT 선택 후 `--skip-compile` 없이 다시 실행합니다.

## 사전 데이터 생성

일반 시뮬레이션에는 Python이 필요하지 않습니다. 모델·입력·가중치·양자화 조건을 변경할 때 다음 명령을 명시적으로 실행합니다. 출력에는 해당 모델의 `weight.bin`도 함께 배치해야 합니다.

```bat
python verification\core\golden_ref\generate_resnet20_core.py --weights tb\libs\models\resnet20\data\weight.bin --out tb\libs\models\resnet20\data
python verification\models\resnet20\generate_partial_fixture.py --weights tb\libs\models\resnet20_partial\data\weight.bin --out tb\libs\models\resnet20_partial\data
python verification\models\toy\generate_fixture.py
```

`toy` 생성기는 별도 가중치 입력 없이 `tb/libs/models/toy/data`에 세 파일을 생성합니다. 출력 경로는 `--out`으로 바꿀 수 있습니다.

TB 실행과 컴파일은 `verification` 소스를 참조하지 않습니다. `verification/models/resnet20`은 별도 가중치와 데이터 생성 도구를 관리합니다. Partial 데이터 생성은 앞단의 float 계산을 수행한 뒤 마지막 블록 입력을 Q5.10으로 양자화합니다.

## 기존 진입점

`behav_sim.sh`는 기존 `tb_core`용 Bash 진입점이며 사전 데이터를 사용합니다. `synthesis.bat tb_core --sim`은 기존 합성 넷리스트를 사용합니다. 합성 도구는 `tb/libs/rtl`을 입력으로 사용하고, 합성 wrapper가 공통 실행기에 넷리스트·대체할 RTL 디렉터리·매크로·추가 elaboration 대상을 전달합니다.
