"""CIFAR-10 ResNet-20 with the chenyaofo checkpoint's projection shortcuts."""

import copy
import hashlib
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn.utils import fuse_conv_bn_eval


CHECKPOINT_NAME = "cifar10_resnet20-4118986f.pt"
CHECKPOINT_URL = (
    "https://github.com/chenyaofo/pytorch-cifar-models/releases/download/resnet/"
    + CHECKPOINT_NAME
)
CHECKPOINT_SHA256 = "4118986f0df73003d572b0e397f0ac7b3f60af1f31aff3d2da164536e36f6ec8"
DEFAULT_BIN = Path(__file__).with_name("weight.bin")
FRAC_BITS = 10
SCALE = 1 << FRAC_BITS
Q_FORMAT = f"Q{15 - FRAC_BITS}.{FRAC_BITS}"
QMIN, QMAX = -32768, 32767
WORD_DTYPE = np.dtype("<i2")


class ResidualAdd(nn.Module):
    def forward(self, main, shortcut):
        return main + shortcut


class BasicBlock(nn.Module):
    def __init__(self, in_channels, out_channels, stride):
        super().__init__()
        # Register the shortcut first to match the Controller's weight stream.
        self.downsample = nn.Identity()
        if stride != 1 or in_channels != out_channels:
            self.downsample = nn.Sequential(
                nn.Conv2d(in_channels, out_channels, 1, stride, bias=False),
                nn.BatchNorm2d(out_channels),
            )
        self.conv1 = nn.Conv2d(in_channels, out_channels, 3, stride, 1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_channels)
        self.conv2 = nn.Conv2d(out_channels, out_channels, 3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_channels)
        self.add = ResidualAdd()
        self.relu = nn.ReLU()

    def forward(self, x):
        main = self.relu(self.bn1(self.conv1(x)))
        main = self.bn2(self.conv2(main))
        return self.relu(self.add(main, self.downsample(x)))


def _stage(in_channels, out_channels, stride):
    return nn.Sequential(
        BasicBlock(in_channels, out_channels, stride),
        BasicBlock(out_channels, out_channels, 1),
        BasicBlock(out_channels, out_channels, 1),
    )


class ResNet20(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(3, 16, 3, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(16)
        self.relu = nn.ReLU()
        self.layer1 = _stage(16, 16, 1)
        self.layer2 = _stage(16, 32, 2)
        self.layer3 = _stage(32, 64, 2)
        self.avgpool = nn.AdaptiveAvgPool2d(1)
        self.fc = nn.Linear(64, 10)

    def forward(self, x):
        x = self.relu(self.bn1(self.conv1(x)))
        x = self.layer3(self.layer2(self.layer1(x)))
        return self.fc(self.avgpool(x).flatten(1))


def checked_asset(path, url, sha256):
    """Use an explicit local file or a verified download in the PyTorch cache."""
    if path is None:
        path = Path(torch.hub.get_dir()) / "checkpoints" / url.rsplit("/", 1)[1]
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            torch.hub.download_url_to_file(url, str(path), hash_prefix=sha256)
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != sha256:
            raise ValueError(f"SHA-256 mismatch: {path}")
    return path


def load_pretrained(checkpoint=None):
    path = checked_asset(checkpoint, CHECKPOINT_URL, CHECKPOINT_SHA256)
    model = ResNet20()
    model.load_state_dict(torch.load(path, map_location="cpu", weights_only=True))
    return model.eval()


def fold_batch_norm(model):
    """Fold each adjacent Conv/BN pair, including both shortcut branches."""
    fused = copy.deepcopy(model).eval()
    for parent in list(fused.modules()):
        children = list(parent.named_children())
        for (conv_name, conv), (bn_name, bn) in zip(children, children[1:]):
            if isinstance(conv, nn.Conv2d) and isinstance(bn, nn.BatchNorm2d):
                setattr(parent, conv_name, fuse_conv_bn_eval(conv, bn))
                setattr(parent, bn_name, nn.Identity())
    return fused


def parameter_layers(model):
    """File order follows registration order, with a block's projection first."""
    for name, layer in model.named_modules():
        if isinstance(layer, (nn.Conv2d, nn.Linear)):
            yield name, layer


def round_to_fixed(values):
    """Scale and round to nearest, breaking ties away from zero."""
    scaled = values.to(torch.float64) * SCALE
    return torch.copysign(torch.floor(scaled.abs() + 0.5), scaled)
