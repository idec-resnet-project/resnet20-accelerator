#!/usr/bin/env python3
"""M3 S1~S3 기준 생성기 — ResNet-20 명령 30개, 디코드, 핑퐁 버퍼 역할, 골든 주소 열.

하는 일
  1) S2  명령 30개를 비트 필드로 만들고 다시 디코드 (Cout·K 규칙 포함), 크기 검산
  2) S3  핑퐁 버퍼(FB0/FB1) + RB + KB + BB 역할표대로 30개 명령을 실행하는 버퍼 모델
  3) S1  명령마다 '매 슬롯 어떤 주소를 읽나' 주소 열 생성 (y→x→oc→term, GAP 층만 oc→y→x→term)
  4) 자체 검사: 주소 열로 계산한 결과 == 버퍼 없이 직접 계산한 결과 (임의 데이터, 30개 명령 전체)

사용
  python3 m3_golden.py                    # 표·검사·미리보기 CSV
  python3 m3_golden.py --trace 1          # 명령 1(conv1) 전체 주소 열 → out/trace_cmd01.txt

정수 규칙 (11/15 RTL 대조 기준, '확인 필요' 표시는 RTL 에서 다시 볼 것)
  acc = (bias << 8) + Σ x·w      (Q7.8 × Q7.8 → Q.16)
  y   = sat16( round_away(acc / 256) )
  residual: y = sat16(y + skip)  ← 포화 위치 확인 필요
  relu: max(y, 0)
  GAP : sat16( round_away(Σ / (Ho·Wo)) )  ← 나눗셈 방식 확인 필요
"""
import argparse, csv, os, sys
import numpy as np

# ── 명령 비트 (pl_interface.md, 11/15) ─────────────────────────────
B_IN, B_OUT, B_GAP, B_RELU, B_RES, B_MAC, B_SKIP = 0, 1, 2, 4, 5, 6, 7
OPS = {"INPUT": 0x01, "SKIP": 0x80, "SKIP_CONV": 0xC0, "CONV_RELU": 0x50,
       "CONV_RES_RELU": 0x70, "CONV_RES_RELU_GAP": 0x74, "FC_OUT": 0x42}
OPNAME = {v: k for k, v in OPS.items()}

BUF_DEPTH = {"FB0": 1 << 14, "FB1": 1 << 14, "RB": 1 << 14, "KB": 1 << 16, "BB": 1 << 6}


def encode(op, W, H, Cin, s=1, pad=0):
    return (OPS[op] | (s - 1) << 8 | pad << 9 | (W - 1) << 10 | (H - 1) << 16 | (Cin - 1) << 22)


def build_commands():
    """ResNet-20 (CIFAR-10, 1×1 projection shortcut) 명령 30개."""
    c = [("input", encode("INPUT", 32, 32, 3)),
         ("conv1", encode("CONV_RELU", 32, 32, 3, 1, 1))]
    W, C = 32, 16
    for stage in range(3):
        for blk in range(3):
            tag = f"s{stage+1}b{blk+1}"
            last = stage == 2 and blk == 2
            res_op = "CONV_RES_RELU_GAP" if last else "CONV_RES_RELU"
            if stage > 0 and blk == 0:          # 다운샘플 블록: 지름길 먼저 (X 가 FB[cur] 에 있을 때)
                c.append((f"{tag}.short", encode("SKIP_CONV", W, W, C, 2, 0)))
                c.append((f"{tag}.convA", encode("CONV_RELU", W, W, C, 2, 1)))
                W, C = W // 2, C * 2
            else:
                c.append((f"{tag}.skip", encode("SKIP", W, W, C)))
                c.append((f"{tag}.convA", encode("CONV_RELU", W, W, C, 1, 1)))
            c.append((f"{tag}.convB", encode(res_op, W, W, C, 1, 1)))
    c.append(("fc", encode("FC_OUT", 1, 1, 64)))
    return c


# ── S2: 디코드 ────────────────────────────────────────────────────
def decode(word):
    op = word & 0xFF
    f = {b: (op >> i) & 1 for b, i in
         [("in", B_IN), ("out", B_OUT), ("gap", B_GAP), ("relu", B_RELU),
          ("res", B_RES), ("mac", B_MAC), ("skip", B_SKIP)]}
    d = dict(f, op=op, name=OPNAME.get(op, "UNKNOWN"),
             s=((word >> 8) & 1) + 1, pad=(word >> 9) & 1,
             W=((word >> 10) & 0x3F) + 1, H=((word >> 16) & 0x3F) + 1,
             Cin=((word >> 22) & 0x3F) + 1)
    # Cout·K 는 명령에 없음 → 규칙으로 (ResNet-20 30개 모두 성립)
    d["K"] = 3 if d["pad"] else 1                       # pad=1 ⇔ 3×3, pad=0 ⇔ 1×1
    if not d["mac"]:
        d["Cout"] = d["Cin"]
    elif d["out"]:
        d["Cout"] = 10                                   # FC
    elif d["Cin"] == 3:
        d["Cout"] = 16                                   # conv1
    elif d["s"] == 2:
        d["Cout"] = 2 * d["Cin"]                         # 다운샘플
    else:
        d["Cout"] = d["Cin"]
    d["Ho"] = d["H"] >> 1 if d["s"] == 2 else d["H"]
    d["Wo"] = d["W"] >> 1 if d["s"] == 2 else d["W"]
    d["N"] = d["Cin"] * d["K"] * d["K"] if d["mac"] else 0
    d["r"] = d["res"]
    d["n_feat_in"] = d["W"] * d["H"] * d["Cin"] if d["in"] else 0
    d["n_kernel"] = d["Cout"] * d["N"]
    d["n_bias"] = d["Cout"] if d["mac"] else 0
    d["n_pix"] = d["Ho"] * d["Wo"] * d["Cout"] if d["mac"] else 0
    d["n_out"] = d["Cout"] if d["gap"] else d["n_pix"]
    d["n_slot"] = d["n_pix"] * (d["N"] + d["r"])
    d["n_copy"] = d["W"] * d["H"] * d["Cin"] if (d["skip"] and not d["mac"]) else 0
    return d


# ── S3: 버퍼 역할 (cur = 지금 활성값이 있는 FB) ─────────────────────
def roles(d, sel):
    cur, nxt = f"FB{sel}", f"FB{1-sel}"
    n = d["name"]
    if n == "INPUT":
        return dict(rd=["stream"], wr=cur, swap=False)
    if n == "SKIP":
        return dict(rd=[cur], wr="RB", swap=False)
    if n == "SKIP_CONV":
        return dict(rd=[cur, "KB", "BB"], wr="RB", swap=False)
    if n == "CONV_RELU":
        return dict(rd=[cur, "KB", "BB"], wr=nxt, swap=True)
    if n in ("CONV_RES_RELU", "CONV_RES_RELU_GAP"):
        return dict(rd=[cur, "KB", "BB", "RB"], wr=nxt, swap=True)
    if n == "FC_OUT":
        return dict(rd=[cur, "KB", "BB"], wr=nxt, swap=False)   # 10 단어 → OUTPUT 상태에서 ODMA 로
    raise ValueError(n)


# ── S1: 주소 열 (슬롯 단위, numpy 벡터) ──────────────────────────────
def schedule(d):
    """슬롯마다 fb_addr(-1=pad), kb_addr, bb_addr(첫 term 만), rb_addr(skip 슬롯만), 출력 쓰기 주소.
    루프: 일반 y→x→oc→term, GAP 층 oc→y→x→term. term = (ic·K+ky)·K+kx, residual 층은 term N = skip."""
    W, H, Cin, Cout, K, s, p = d["W"], d["H"], d["Cin"], d["Cout"], d["K"], d["s"], d["pad"]
    Ho, Wo, N, r = d["Ho"], d["Wo"], d["N"], d["r"]
    if d["gap"]:
        oc, y, x = np.meshgrid(np.arange(Cout), np.arange(Ho), np.arange(Wo), indexing="ij")
    else:
        y, x, oc = np.meshgrid(np.arange(Ho), np.arange(Wo), np.arange(Cout), indexing="ij")
    y, x, oc = y.ravel(), x.ravel(), oc.ravel()            # 출력(픽셀) 순서
    t = np.arange(N)
    ic, ky, kx = t // (K * K), (t // K) % K, t % K
    iy = y[:, None] * s + ky[None, :] - p
    ix = x[:, None] * s + kx[None, :] - p
    valid = (iy >= 0) & (iy < H) & (ix >= 0) & (ix < W)
    fb = np.where(valid, (iy * W + ix) * Cin + ic[None, :], -1)
    kb = oc[:, None] * N + t[None, :]
    rb = (y * Wo + x) * Cout + oc                          # skip 주소 = 출력 위치
    out_addr = oc if d["gap"] else (y * Wo + x) * Cout + oc
    return dict(y=y, x=x, oc=oc, fb=fb, kb=kb, bb=oc, rb=rb, out_addr=out_addr, N=N, r=r)


def rnd_div(v, sh):
    """0에서 먼 쪽 반올림 나눗셈 (÷2^sh)."""
    a = np.abs(v)
    return np.sign(v) * ((a + (1 << (sh - 1))) >> sh)


def rnd_div_n(v, n):
    a = np.abs(v)
    return np.sign(v) * ((a + n // 2) // n)


sat16 = lambda v: np.clip(v, -32768, 32767)


def run_scheduled(d, sc, buf, rd, wr):
    """주소 열만 써서 버퍼에서 읽고 계산 → wr 버퍼에 씀 (S1·S3 검사용)."""
    fbuf = buf[rd[0]]
    xs = np.where(sc["fb"] >= 0, fbuf[np.maximum(sc["fb"], 0)], 0).astype(np.int64)
    ws = buf["KB"][sc["kb"]].astype(np.int64)
    acc = (buf["BB"][sc["bb"]].astype(np.int64) << 8) + (xs * ws).sum(1)
    v = sat16(rnd_div(acc, 8))
    if d["res"]:
        v = sat16(v + buf["RB"][sc["rb"]])
    if d["relu"]:
        v = np.maximum(v, 0)
    if d["gap"]:
        v = sat16(rnd_div_n(v.reshape(d["Cout"], -1).sum(1), d["Ho"] * d["Wo"]))
        buf[wr][:d["Cout"]] = v                            # GAP: oc 마다 1 단어, 주소 = oc
        return sc
    buf[wr][sc["out_addr"]] = v
    return sc


# ── 버퍼 없는 직접 계산 (정답) ─────────────────────────────────────
def conv_direct(x, w, b, s, p):
    H, W, Cin = x.shape
    Cout, _, K, _ = w.shape
    xp = np.pad(x, ((p, p), (p, p), (0, 0))).astype(np.int64)
    Ho, Wo = (H + 2 * p - K) // s + 1, (W + 2 * p - K) // s + 1
    acc = np.zeros((Ho, Wo, Cout), np.int64) + (b.astype(np.int64) << 8)
    for ky in range(K):
        for kx in range(K):
            patch = xp[ky:ky + s * Ho:s, kx:kx + s * Wo:s, :]
            acc += np.einsum("hwc,oc->hwo", patch, w[:, :, ky, kx].astype(np.int64))
    return sat16(rnd_div(acc, 8))


def net_direct(img, params):
    """img HWC, params: 명령 순서대로 (w,b) 리스트(mac 명령만)."""
    it = iter(params)
    a = np.maximum(conv_direct(img, *next(it), 1, 1), 0)
    for stage in range(3):
        for blk in range(3):
            if stage > 0 and blk == 0:
                sc = conv_direct(a, *next(it), 2, 0)
                h = np.maximum(conv_direct(a, *next(it), 2, 1), 0)
            else:
                sc = a
                h = np.maximum(conv_direct(a, *next(it), 1, 1), 0)
            a = np.maximum(sat16(conv_direct(h, *next(it), 1, 1) + sc), 0)
    g = sat16(rnd_div_n(a.reshape(-1, a.shape[2]).sum(0), a.shape[0] * a.shape[1]))
    w, b = next(it)
    return conv_direct(g.reshape(1, 1, -1), w, b, 1, 0).ravel(), params


def run_network(cmds, img, params, trace_rows=None):
    """역할표 + 주소 열로 30개 명령 실행. 버퍼 용량·읽기 전 쓰기 여부도 검사."""
    buf = {k: np.zeros(v, np.int64) for k, v in BUF_DEPTH.items()}
    written = {k: np.zeros(v, bool) for k, v in BUF_DEPTH.items()}
    peak = {k: 0 for k in BUF_DEPTH}
    sel, it, log = 0, iter(params), []
    dumps = []
    for i, (tag, word) in enumerate(cmds):
        d = decode(word)
        R = roles(d, sel)
        if d["in"]:
            flat = img.ravel()
            buf[R["wr"]][:flat.size] = flat
            written[R["wr"]][:flat.size] = True
            peak[R["wr"]] = max(peak[R["wr"]], flat.size)
        elif d["skip"] and not d["mac"]:                    # SKIP: FB[cur] → RB 같은 주소 복사
            n = d["n_copy"]
            assert written[R["rd"][0]][:n].all(), f"{tag}: 읽기 전 미기록"
            buf["RB"][:n] = buf[R["rd"][0]][:n]
            written["RB"][:n] = True
            peak["RB"] = max(peak["RB"], n)
        else:
            w, b = next(it)
            kflat = w.reshape(d["Cout"], -1)                # [oc][ic][ky][kx] 연속
            buf["KB"][:kflat.size] = kflat.ravel(); written["KB"][:] = False; written["KB"][:kflat.size] = True
            buf["BB"][:b.size] = b; written["BB"][:] = False; written["BB"][:b.size] = True
            peak["KB"] = max(peak["KB"], kflat.size); peak["BB"] = max(peak["BB"], b.size)
            sc = schedule(d)
            fbr = sc["fb"][sc["fb"] >= 0]
            assert written[R["rd"][0]][fbr].all(), f"{tag}: FB 미기록 읽기"
            if d["res"]:
                assert written["RB"][sc["rb"]].all(), f"{tag}: RB 미기록 읽기"
            for k, a in (("KB", sc["kb"]), ("BB", sc["bb"]), (R["wr"], sc["out_addr"])):
                assert a.max() < BUF_DEPTH[k], f"{tag}: {k} 용량 초과"
            run_scheduled(d, sc, buf, R["rd"], R["wr"])
            written[R["wr"]][sc["out_addr"]] = True
            peak[R["wr"]] = max(peak[R["wr"]], int(sc["out_addr"].max()) + 1)
            peak[R["rd"][0]] = max(peak[R["rd"][0]], int(fbr.max()) + 1)
        log.append(dict(i=i, tag=tag, sel_before=sel, **R))
        if d["mac"]:
            dumps.append((i, tag, R["wr"], buf[R["wr"]][:d["n_out"]].copy()))
        if R["swap"]:
            sel ^= 1
    run_network.dumps = dumps
    return buf[f"FB{1-sel}"][:10].copy(), log, peak


# ── 출력 ──────────────────────────────────────────────────────────
def write_tables(cmds, log, outdir):
    os.makedirs(outdir, exist_ok=True)
    rows = []
    for (tag, word), L in zip(cmds, log):
        d = decode(word)
        rows.append(dict(idx=L["i"], tag=tag, op=d["name"], word=f"0x{word:08X}",
                         W=d["W"], H=d["H"], Cin=d["Cin"], Cout=d["Cout"], K=d["K"], s=d["s"], pad=d["pad"],
                         Ho=d["Ho"], Wo=d["Wo"], N=d["N"], r=d["r"],
                         feat_in=d["n_feat_in"], kernel=d["n_kernel"], bias=d["n_bias"],
                         copy=d["n_copy"], out=d["n_out"], slots=d["n_slot"],
                         read="+".join(L["rd"]), write=L["wr"],
                         sel=f"{L['sel_before']}->{L['sel_before'] ^ int(L['swap'])}"))
    with open(os.path.join(outdir, "commands_30.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    return rows


def write_trace(d, path, limit=None):
    sc = schedule(d)
    N, r = sc["N"], sc["r"]
    grp = d["Ho"] * d["Wo"] if d["gap"] else 1             # GAP: Ho·Wo 픽셀마다 출력 1개
    with open(path, "w") as f:
        f.write("slot,pix,y,x,oc,term,kind,fb_addr,kb_addr,bb_addr,rb_addr,first,last,out_addr\n")
        slot = 0
        for p in range(len(sc["y"])):
            for t in range(N + r):
                if limit is not None and slot >= limit:
                    return
                is_skip = t == N
                fb = "" if is_skip else ("PAD" if sc["fb"][p, t] < 0 else sc["fb"][p, t])
                f.write(f"{slot},{p},{sc['y'][p]},{sc['x'][p]},{sc['oc'][p]},{t},"
                        f"{'skip' if is_skip else 'mac'},{fb},"
                        f"{'' if is_skip else sc['kb'][p, t]},{sc['bb'][p] if t == 0 else ''},"
                        f"{sc['rb'][p] if is_skip else ''},{int(t == 0)},{int(t == N + r - 1)},"
                        f"{sc['out_addr'][p] if (t == N + r - 1 and p % grp == grp - 1) else ''}\n")
                slot += 1


def rand_params(cmds, rng):
    ps = []
    for _, word in cmds:
        d = decode(word)
        if d["mac"]:
            ps.append((rng.integers(-24, 25, (d["Cout"], d["Cin"], d["K"], d["K"])),
                       rng.integers(-512, 513, d["Cout"])))
    return ps


def load_weights(cmds, path):
    """weight.bin: 명령 순서대로 레이어마다 커널 전체 → bias 전체 (int16 LE)."""
    w = np.fromfile(path, "<i2").astype(np.int64)
    ps, off = [], 0
    for _, word in cmds:
        d = decode(word)
        if not d["mac"]:
            continue
        nk = d["n_kernel"]
        k = w[off:off + nk].reshape(d["Cout"], d["Cin"], d["K"], d["K"]); off += nk
        b = w[off:off + d["Cout"]]; off += d["Cout"]
        ps.append((k, b))
    assert off == w.size, (off, w.size)
    return ps


def load_input(path):
    v = [int(t, 16) for t in open(path).read().split()]
    v = np.array([x - 65536 if x >= 32768 else x for x in v], np.int64)
    return v.reshape(32, 32, 3)                            # 스트림 순서 = HWC


def net_float(img, params):
    """resnet20_compute.c 와 같은 float 경로 (입력·가중치만 Q7.8)."""
    f = lambda a: a.astype(np.float64) / 256
    def conv(x, w, b, s, p):
        H, W, _ = x.shape; K = w.shape[2]
        xp = np.pad(x, ((p, p), (p, p), (0, 0)))
        Ho, Wo = (H + 2 * p - K) // s + 1, (W + 2 * p - K) // s + 1
        o = np.zeros((Ho, Wo, w.shape[0])) + f(b)
        for ky in range(K):
            for kx in range(K):
                o += np.einsum("hwc,oc->hwo", xp[ky:ky + s * Ho:s, kx:kx + s * Wo:s], f(w[:, :, ky, kx]))
        return o
    it = iter(params)
    a = np.maximum(conv(f(img), *next(it), 1, 1), 0)
    for stage in range(3):
        for blk in range(3):
            if stage > 0 and blk == 0:
                sc = conv(a, *next(it), 2, 0); h = np.maximum(conv(a, *next(it), 2, 1), 0)
            else:
                sc = a; h = np.maximum(conv(a, *next(it), 1, 1), 0)
            a = np.maximum(conv(h, *next(it), 1, 1) + sc, 0)
    g = a.reshape(-1, a.shape[2]).mean(0)
    w, b = next(it)
    return conv(g.reshape(1, 1, -1), w, b, 1, 0).ravel()


def snr_db(ref, test):
    ref, test = np.asarray(ref, float), np.asarray(test, float)
    return 10 * np.log10((ref ** 2).sum() / ((ref - test) ** 2).sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="out")
    ap.add_argument("--trace", type=int, default=None, help="이 명령 번호의 전체 주소 열을 씀")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--weights", help="weight.bin (Q7.8)")
    ap.add_argument("--input", help="input_q7_8.hex (HWC 스트림 순서)")
    ap.add_argument("--ref", help="reference_logits_float.txt")
    a = ap.parse_args()

    cmds = build_commands()
    ds = [decode(w) for _, w in cmds]
    assert len(cmds) == 30
    k = sum(d["n_kernel"] for d in ds); b = sum(d["n_bias"] for d in ds)
    print(f"명령 {len(cmds)}개 · kernel {k:,} · bias {b:,} · 합 {k+b:,} 단어 = {2*(k+b):,} B")
    assert (k, b) == (270_896, 794), "weight.bin 크기와 다름"
    slots = sum(d["n_slot"] for d in ds)
    print(f"RUN 슬롯 합 {slots:,} · 최대 {max(d['n_slot'] for d in ds):,} (명령 {np.argmax([d['n_slot'] for d in ds])})")
    # 디코드 왕복
    for (tag, w), d in zip(cmds, ds):
        assert encode(d["name"], d["W"], d["H"], d["Cin"], d["s"], d["pad"]) == w, tag

    # 자체 검사: 주소 열 + 역할표 실행 == 직접 계산
    for seed in range(a.seeds):
        rng = np.random.default_rng(seed)
        img = rng.integers(-256, 257, (32, 32, 3))
        ps = rand_params(cmds, rng)
        got, log, peak = run_network(cmds, img, ps)
        ref, _ = net_direct(img, ps)
        ok = np.array_equal(got, ref)
        print(f"seed {seed}: 로짓 일치 {ok}  {got.tolist()}")
        assert ok
    print("버퍼 최대 사용(단어):", {k: f"{v:,}/{BUF_DEPTH[k]:,}" for k, v in peak.items()})

    rows = write_tables(cmds, log, a.out)
    if a.weights and a.input:
        ps = load_weights(cmds, a.weights)
        img = load_input(a.input)
        got, _, _ = run_network(cmds, img, ps)
        ref_int, _ = net_direct(img, ps)
        assert np.array_equal(got, ref_int)
        gdir = os.path.join(a.out, "golden"); os.makedirs(gdir, exist_ok=True)
        for i, tag, wr, v in run_network.dumps:
            with open(os.path.join(gdir, f"cmd{i:02d}_{tag}_{wr}.hex"), "w") as f:
                f.write("\n".join(f"{int(x) & 0xFFFF:04x}" for x in v) + "\n")
        print("실제 데이터 정수 로짓 (Q7.8):", got.tolist())
        print("  실수값:", [round(x / 256, 4) for x in got.tolist()], " argmax", int(np.argmax(got)))
        if a.ref:
            ref = np.loadtxt(a.ref)
            fl = net_float(img, ps)
            print(f"float 재현 vs 참조 파일 최대 차 {np.abs(fl - ref).max():.2e}")
            print(f"정수 경로 vs 참조 float SNR {snr_db(ref, got / 256):.2f} dB · argmax 참조 {int(np.argmax(ref))}")
        print("층별 골든:", gdir)
    write_trace(ds[1], os.path.join(a.out, "trace_cmd01_head.csv"), limit=120)
    if a.trace is not None:
        write_trace(ds[a.trace], os.path.join(a.out, f"trace_cmd{a.trace:02d}.csv"))
        print("전체 주소 열:", os.path.join(a.out, f"trace_cmd{a.trace:02d}.csv"))
    print("표:", os.path.join(a.out, "commands_30.csv"))


if __name__ == "__main__":
    main()
