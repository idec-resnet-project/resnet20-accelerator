# ResNet-20 `weight.bin` 사양

대상 모델은 CIFAR-10 입력 `N×3×32×32`를 받아 10개 로짓을 내는 `chenyaofo/pytorch-cifar-models`의 ResNet-20이다. `layer2.0`과 `layer3.0`은 stride 2의 `1×1` projection shortcut을 쓴다. Conv 21개에 추론용 BatchNorm을 접고 FC 1개를 그대로 내보낸다. [모델 소스](https://github.com/chenyaofo/pytorch-cifar-models/blob/master/pytorch_cifar_models/resnet.py) · [사전 학습 체크포인트](https://github.com/chenyaofo/pytorch-cifar-models/releases/download/resnet/cifar10_resnet20-4118986f.pt)

## 파일 구성

- 워드 형식은 **부호 있는 16비트 2의 보수, little-endian, Q5.10**이다. 정수 워드 `q`의 실수값은 `q / 1024`이다. 실수 범위는 `−32`부터 `31.9990234375`까지다.
- 양자화는 `q = sign(x) × floor(abs(x) × 1024 + 0.5)`를 사용한다. 반올림 결과가 int16 범위를 벗어나면 추출을 중단한다.
- 레이어마다 **가중치 전체 → bias 전체**를 이어서 쓴다. 헤더, 레이어 구분자, 정렬 패딩은 없다. bias는 출력 채널 인덱스가 증가하는 순서다.
- 총 270,896개 가중치와 794개 bias가 들어 있다. 파일 크기는 **543,380바이트**다.
- SHA-256은 `549020eba9a23f1c60694839a2ca07b9ece22267dbee886bee7f6a92c242b992`다.

### 워드 순서와 주소

**빠르게 바뀌는 축부터 `width → height → depth → channel`**이다. Conv 가중치의 `width`, `height`는 커널의 `kx`, `ky`, `depth`는 입력 채널 `ic`, 마지막 `channel`은 출력 채널 `oc`다. 아래 식의 좌표는 모두 0부터 시작한다. 기존 [bottleneck 커널 주소식](../docs/appendix.md)은 입력 채널이 가장 빠르게 바뀌므로, 이 파일을 읽는 주소식은 아래 식을 사용한다.

```text
conv_index(oc, ic, ky, kx) = ((oc * Cin + ic) * Kh + ky) * Kw + kx
conv_byte = weight_offset + 2 * conv_index(oc, ic, ky, kx)
fc_byte   = weight_offset + 2 * (oc * 64 + ic)
bias_byte = bias_offset   + 2 * oc
```

#### 커널 저장 예시

입력 채널과 출력 채널이 각각 1개인 `4×4` feature map과 `2×2` 커널을 예로 든다. stride는 1, padding은 0, bias는 `0.5`이므로 출력은 `3×3`이다.

```text
4×4 입력 feature map        2×2 커널
 1   2   3   4               1   0.5
 5   6   7   8              -1   0.25
 9  10  11  12
13  14  15  16
```

커널의 위쪽 행을 왼쪽에서 오른쪽으로 쓴 뒤 아래쪽 행을 쓴다. `weight.bin`에서 이 레이어의 저장 순서는 다음과 같다. Feature map은 추론 시 별도로 들어오는 입력이다.

| 구분 | 저장 순서 | Q5.10 정수 워드 | 레이어 시작 기준 바이트 오프셋 |
|---|---|---|---|
| 커널 | `1, 0.5, -1, 0.25` | `1024, 512, -1024, 256` | `0, 2, 4, 6` |
| Bias | `0.5` | `512` | `8` |

왼쪽 위 출력은 feature map의 첫 `2×2` 영역으로 계산한다. `1×1 + 2×0.5 + 5×(−1) + 6×0.25 + 0.5 = −1`이다. 입력 채널이 여러 개면 같은 출력 채널의 `2×2` 커널을 입력 채널 순으로 이어 쓰고, 그다음 출력 채널로 넘어간다.

실제 첫 Conv의 `w[0,0,0,0]`, `w[0,0,0,1]`, `w[0,0,1,0]`, `w[0,1,0,0]`은 각각 바이트 `0`, `2`, `6`, `18`에서 시작한다.

Projection이 있는 블록은 Controller의 `SKIP_CONV → CONV_RELU → CONV_RESIDUAL_RELU` 실행 순서에 맞춰 **`downsample.0 → conv1 → conv2`** 순서로 배치한다. 각 레이어는 커널 전체를 쓴 뒤 bias 전체를 쓴다. Identity `SKIP`은 파일에서 소비할 워드가 없다.

| 레이어 | 커널 / stride | Cin→Cout | 가중치 개수 | Weight 바이트 오프셋 | Bias 바이트 오프셋 |
|---|---|---|---:|---:|---:|
| `conv1` | `3×3 / 1` | `3→16` | 432 | 0 | 864 |
| `layer1.0.conv1` | `3×3 / 1` | `16→16` | 2,304 | 896 | 5,504 |
| `layer1.0.conv2` | `3×3 / 1` | `16→16` | 2,304 | 5,536 | 10,144 |
| `layer1.1.conv1` | `3×3 / 1` | `16→16` | 2,304 | 10,176 | 14,784 |
| `layer1.1.conv2` | `3×3 / 1` | `16→16` | 2,304 | 14,816 | 19,424 |
| `layer1.2.conv1` | `3×3 / 1` | `16→16` | 2,304 | 19,456 | 24,064 |
| `layer1.2.conv2` | `3×3 / 1` | `16→16` | 2,304 | 24,096 | 28,704 |
| `layer2.0.downsample.0` | `1×1 / 2` | `16→32` | 512 | 28,736 | 29,760 |
| `layer2.0.conv1` | `3×3 / 2` | `16→32` | 4,608 | 29,824 | 39,040 |
| `layer2.0.conv2` | `3×3 / 1` | `32→32` | 9,216 | 39,104 | 57,536 |
| `layer2.1.conv1` | `3×3 / 1` | `32→32` | 9,216 | 57,600 | 76,032 |
| `layer2.1.conv2` | `3×3 / 1` | `32→32` | 9,216 | 76,096 | 94,528 |
| `layer2.2.conv1` | `3×3 / 1` | `32→32` | 9,216 | 94,592 | 113,024 |
| `layer2.2.conv2` | `3×3 / 1` | `32→32` | 9,216 | 113,088 | 131,520 |
| `layer3.0.downsample.0` | `1×1 / 2` | `32→64` | 2,048 | 131,584 | 135,680 |
| `layer3.0.conv1` | `3×3 / 2` | `32→64` | 18,432 | 135,808 | 172,672 |
| `layer3.0.conv2` | `3×3 / 1` | `64→64` | 36,864 | 172,800 | 246,528 |
| `layer3.1.conv1` | `3×3 / 1` | `64→64` | 36,864 | 246,656 | 320,384 |
| `layer3.1.conv2` | `3×3 / 1` | `64→64` | 36,864 | 320,512 | 394,240 |
| `layer3.2.conv1` | `3×3 / 1` | `64→64` | 36,864 | 394,368 | 468,096 |
| `layer3.2.conv2` | `3×3 / 1` | `64→64` | 36,864 | 468,224 | 541,952 |
| `fc` | — | `64→10` | 640 | 542,080 | 543,360 |

## 추론 수치 규칙

BN 폴딩은 채널별 `a = γ / sqrt(running_var + ε)`를 계산해 `W′ = a × W`, `b′ = β + a × (b − running_mean)`으로 변환한다. 이 모델의 원본 Conv에는 bias가 없으므로 `b = 0`이다. projection shortcut도 동일한 규칙으로 접는다.

1. RGB `uint8` 픽셀을 `p / 255`로 변환한 뒤 `(p / 255 − mean) / std`로 정규화한다. `mean = (0.4914, 0.4822, 0.4465)`, `std = (0.2023, 0.1994, 0.2010)`이다. 전체 고정소수점 모사에서는 이 값을 Q5.10으로 변환한다. [학습 설정](https://github.com/chenyaofo/image-classification-codebase/blob/19a5ce6/conf/cifar10.conf)
2. Conv는 cross-correlation을 수행한다. `3×3` Conv는 양쪽에 0을 1칸씩 패딩하고 `1×1` Conv는 padding 0이다. Conv와 FC는 `acc = Σ(xq × wq) + (bq × 1024)`을 누산한 뒤 `sat16(round(acc / 1024))`을 출력한다. RTL에서는 bias를 10비트 왼쪽으로 시프트해 더하고, 반올림과 함께 10비트 오른쪽으로 시프트해 출력 스케일을 맞춘다. 최대 누산 길이는 576이다. 모든 int16 입력을 지원하려면 부호 있는 41비트 이상이 필요하며 64비트 누산기를 사용할 수 있다.
3. stem Conv 다음에 ReLU를 적용한다. 각 블록은 `Conv → ReLU → Conv`를 계산하고, 블록 입력 또는 projection 결과를 더해 int16으로 포화한 뒤 ReLU를 적용한다.
4. GAP는 각 채널의 `8×8`을 더해 64로 나눈 뒤 반올림한다. FC 출력은 로짓이며 분류는 `argmax`로 계산한다. 모든 반올림의 정확한 중간값은 0에서 먼 쪽으로 보낸다.

검증기는 MAC을 `float64`로 계산한 뒤 정수로 변환한다. 최대 576개 int16 곱과 스케일을 맞춘 bias의 절댓값 합이 `2^53` 미만이므로 정수 곱·누산을 정확히 표현할 수 있다. 재양자화, residual 덧셈, GAP에는 정수 연산을 사용한다.

## 재현 및 검증

Python 3.11 이상에서 `torch`, `numpy`, `pyarrow`, `Pillow`를 설치하고 이 폴더에서 실행한다.

```sh
python extract_bin.py
python verify_bin.py --samples 10000
```

최초 실행 시 공개 체크포인트와 [CIFAR-10 테스트 Parquet](https://huggingface.co/datasets/uoft-cs/cifar10/tree/main/plain_text)를 PyTorch 캐시에 내려받고 SHA-256을 확인한다. 로컬 파일은 `--checkpoint`와 `--test-parquet`로 지정한다. 기본 검증은 테스트 순서의 첫 1,024장을 사용한다.

원본 FP32 모델의 로짓을 기준으로 전체 이미지와 클래스에 대해 `SNR = 10 log10(Σref² / Σ(ref − test)²)`를 계산한다. BN 폴딩만 한 FP32, bin에서 읽은 가중치와 bias만 Q5.10인 모델, 활성값까지 Q5.10인 모델을 각각 비교한다. 두 bin 실행의 기본 판정 기준은 기존 프로젝트의 수치 판정 기준과 같은 30 dB다. `--min-snr`로 변경할 수 있다. [기존 프로젝트 수치 판정](../docs/appendix.md#수치--판정)

### CIFAR-10 테스트 이미지 10,000장 실측

| 실행 | 로짓 SNR | Top-1 정확도 | FP32 예측 일치율 |
|---|---:|---:|---:|
| 원본 FP32 | — | 92.60% | — |
| BN 폴딩 FP32 | 127.27 dB | 92.60% | 100.00% |
| Q5.10 가중치·bias, FP32 활성값 | 39.67 dB | 92.60% | 99.77% |
| Q5.10 전체 추론 | 39.57 dB | 92.62% | 99.76% |

접은 가중치의 최대 절댓값은 3.064939, bias는 0.947197이었다. Q5.10은 두 bin 실행 모두 30 dB를 넘겼다. 같은 테스트에서 Q7.8 전체 추론은 25.64 dB와 정확도 92.33%를 기록했다.
