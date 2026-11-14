# TB 옵션

| 실행 명령 | 대상 |
|---|---|
| `./scripts/behav_sim.sh [tb_name] [--options]` | behavior simulation |


| Windows 옵션 | 동작 |
|---|---|
| `--gui` | 실행 후 저장된 WDB 열기 |
| `--gui-live` | 라이브 파형 창에서 실행. `--gui`와 택일 |
| `--no-wdb` | 결과 WDB 저장 생략 |
| `--skip-compile` | 같은 모드의 스냅샷 및 생성된 벡터 재사용 |

## 파일 구조

```text
tb/
  {tb_name}/
    {tb_name}.f     # source file path set
    {tb_name}.sv    # tb file
    {tb_name}.wcfg  # wave preset, 파일이 존재한다면 자동 적용.          
```
