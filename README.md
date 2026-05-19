# jellyfin-nvv4l2-wrapper

[English](#english) | [日本語](#日本語)

---

## English

### Overview

An FFmpeg wrapper script that enables **Jellyfin hardware-accelerated HLS transcoding** on **Nintendo Switch** running L4T Ubuntu, using the Tegra X1's `h264_nvv4l2` / `hevc_nvv4l2` hardware encoder.

Jellyfin does not natively support the `nvv4l2` encoder family in its UI. This wrapper transparently intercepts FFmpeg calls from Jellyfin, replacing `libx264`/`libx265` with the hardware encoder and adjusting incompatible options.

**Tested with**: Jellyfin 10.11.9 (apt version)

### The Problem

| Issue | Description |
|---|---|
| **No UI support** | Jellyfin's transcoding settings do not list `h264_nvv4l2` as an available encoder |
| **No IDR frames** | `h264_nvv4l2` does not generate IDR frames; the `-g` (GOP size) and `-force_key_frames` options are ignored |
| **HLS segmentation failure** | Without IDR frames, the HLS fMP4 muxer cannot split segments at keyframe boundaries, resulting in a single unsegmented output |
| **ffprobe contamination** | The NVMEDIA library prints debug messages (`Opening in BLOCKING MODE`, etc.) to stdout, corrupting ffprobe's JSON output and causing Jellyfin's Probe Provider to fail |

### How It Works

```
Jellyfin → jellyfin-nvv4l2-wrapper → /usr/bin/ffmpeg
              │
              ├─ libx264 → h264_nvv4l2
              ├─ libx265 → hevc_nvv4l2
              ├─ Removes: -crf, -x264opts, -force_key_frames, -preset (string), -sc_threshold
              ├─ Adds: -hls_flags split_by_time  (when fMP4 segment type)
              └─ Stream copy: passthrough (no modification)
```

The key fix is `-hls_flags split_by_time`, which forces the HLS muxer to split segments based on time rather than waiting for IDR frames.

### Requirements

- **Hardware**: Nintendo Switch (Tegra X1)
- **OS**: L4T Ubuntu (24.04)
- **FFmpeg**: [FFmpeg with nvv4l2 support](https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2) — FFmpeg with nvv4l2 support for Tegra
- **Jellyfin**: 10.11.9 (apt version). Docker, Snap, and Flatpak versions are untested.

### Installing FFmpeg

If FFmpeg with nvv4l2 support is not installed, please obtain it from [theofficialgman/FFmpeg (6.1.1-nvv4l2 branch)](https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2). 

For L4T Ubuntu 24.04, pre-built packages (e.g., `ffmpeg 6.1.1-3ubuntu5l4t2`) may be available via apt depending on your distribution setup.

Verify that `h264_nvv4l2` is available:

```bash
ffmpeg -encoders 2>/dev/null | grep nvv4l2
```

### Installation

```bash
git clone https://github.com/YOUR_USERNAME/jellyfin-nvv4l2-wrapper.git
cd jellyfin-nvv4l2-wrapper
sudo bash install.sh
sudo systemctl restart jellyfin
```

The installer automatically:
1. Copies wrapper scripts to `/usr/local/bin/`
2. Configures ffprobe filtering
3. Sets the FFmpeg path in `/etc/default/jellyfin` (apt version only)

### Manual Installation

```bash
# Copy scripts
sudo cp jellyfin-nvv4l2-wrapper /usr/local/bin/
sudo cp ffprobe-wrapper /usr/local/bin/
sudo chmod +x /usr/local/bin/jellyfin-nvv4l2-wrapper
sudo chmod +x /usr/local/bin/ffprobe-wrapper

# Replace ffprobe symlink (filters NVMEDIA stdout contamination)
sudo ln -sf /usr/local/bin/ffprobe-wrapper /usr/local/bin/ffprobe
```

Then configure the FFmpeg path for Jellyfin (apt version):

```bash
sudo nano /etc/default/jellyfin
```

Find the `JELLYFIN_FFMPEG_OPT` line (add it if it doesn't exist) and set:

```bash
JELLYFIN_FFMPEG_OPT="--ffmpeg /usr/local/bin/jellyfin-nvv4l2-wrapper"
```

Restart Jellyfin:

```bash
sudo systemctl restart jellyfin
```

> **Note**: The Jellyfin web UI no longer allows editing the FFmpeg path directly in recent versions. The `/etc/default/jellyfin` configuration file method shown above is required. This method only applies to the apt-installed version of Jellyfin.

### Uninstallation

```bash
cd jellyfin-nvv4l2-wrapper
sudo bash uninstall.sh
sudo systemctl restart jellyfin
```

### Verifying Operation

Check the wrapper log:

```bash
# View the latest ffmpeg invocation and rewritten args
tail -20 /tmp/jellyfin-ffmpeg-wrapper.log
```

You should see:
- `ARGS:` — the original arguments from Jellyfin (containing `libx264`)
- `NEW_ARGS:` — the rewritten arguments (containing `h264_nvv4l2` and `-hls_flags split_by_time`)

For stream-copy operations (no `libx264`/`libx265` in args), you should see:
- `NEW_ARGS(passthrough):` — arguments passed through unchanged

### Known Limitations

- **No IDR frame control**: `h264_nvv4l2` ignores `-g`, `-force_key_frames`, and `-forced-idr`. The `split_by_time` flag works around this but may cause slightly less accurate seeking.
- **Stream copy is unmodified**: When Jellyfin decides to remux without transcoding, the wrapper passes all arguments through unchanged. This is correct behavior.
- **Encoding quality**: Without `-crf`, `h264_nvv4l2` uses its internal default quality settings. Bitrate is still controlled by Jellyfin's `-maxrate` and `-bufsize` parameters.
- **Profile/Level**: The wrapper preserves Jellyfin's `-profile` and `-level` flags, but `h264_nvv4l2` may not support all combinations (e.g., High profile may fall back to Main).
- **apt only**: Only the apt-installed version of Jellyfin is supported by the installer. Docker, Snap, and Flatpak versions are untested.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Playback doesn't start | Check if segments are generated in `/var/cache/jellyfin/transcodes/` | Review `/tmp/jellyfin-ffmpeg-wrapper.log` for errors |
| `Error in Probe Provider` in Jellyfin log | NVMEDIA debug output corrupting ffprobe JSON | Ensure ffprobe symlink points to `ffprobe-wrapper` |
| Encoding runs but no segments | `split_by_time` flag missing | Check `NEW_ARGS` in log for `-hls_flags split_by_time` |
| Video plays but seeking is inaccurate | Expected limitation of `split_by_time` without IDR frames | Normal behavior for nvv4l2 |

---

## 日本語

### 概要

**Nintendo Switch** (L4T Ubuntu) 上の **Jellyfin** で、Tegra X1 のハードウェアエンコーダ (`h264_nvv4l2` / `hevc_nvv4l2`) を利用した **HLSハードウェアトランスコード** を実現するFFmpegラッパースクリプトです。

JellyfinのUIでは `nvv4l2` エンコーダファミリを選択できません。このラッパーはJellyfinからのFFmpeg呼び出しを透過的にインターセプトし、`libx264`/`libx265` をハードウェアエンコーダに置換し、互換性のないオプションを調整します。

**動作確認環境**: Jellyfin 10.11.9 (apt版)

### 解決する問題

| 問題 | 説明 |
|---|---|
| **UIで選択不可** | Jellyfinのトランスコード設定に `h264_nvv4l2` が表示されない |
| **IDRフレーム未生成** | `h264_nvv4l2` はIDRフレームを生成しない。`-g` (GOPサイズ) や `-force_key_frames` オプションは無視される |
| **HLSセグメント分割失敗** | IDRフレームがないため、HLS fMP4マルチプレクサがキーフレーム境界でセグメント分割できず、出力が単一ファイルになる |
| **ffprobe出力汚染** | NVMEDIAライブラリがデバッグメッセージ (`Opening in BLOCKING MODE` 等) をstdoutに出力し、ffprobeのJSON出力が壊れてJellyfinのProbe Providerがエラーになる |

### 動作の仕組み

```
Jellyfin → jellyfin-nvv4l2-wrapper → /usr/bin/ffmpeg
              │
              ├─ libx264 → h264_nvv4l2
              ├─ libx265 → hevc_nvv4l2
              ├─ 削除: -crf, -x264opts, -force_key_frames, -preset (文字列), -sc_threshold
              ├─ 追加: -hls_flags split_by_time (fMP4セグメントタイプ時)
              └─ ストリームコピー: パススルー (変更なし)
```

重要な修正点は `-hls_flags split_by_time` の追加です。これによりHLSマルチプレクサがIDRフレームを待たず、時間ベースでセグメントを強制分割します。

### 前提条件

- **ハードウェア**: Nintendo Switch (Tegra X1)
- **OS**: L4T Ubuntu (24.04)
- **FFmpeg**: [nvv4l2対応FFmpeg](https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2) — Tegra向けnvv4l2対応FFmpeg
- **Jellyfin**: 10.11.9 (apt版)。Docker版、Snap版、Flatpak版は未検証。

### FFmpeg のインストール

nvv4l2対応FFmpegがインストールされていない場合、[theofficialgman/FFmpeg (6.1.1-nvv4l2 ブランチ)](https://github.com/theofficialgman/FFmpeg/tree/6.1.1-nvv4l2) から入手してください。

L4T Ubuntu 24.04環境では、OSのセットアップ状況によりビルド済みパッケージ（例: `ffmpeg 6.1.1-3ubuntu5l4t2`）がapt経由で利用可能な場合があります。

`h264_nvv4l2` が利用可能か確認：

```bash
ffmpeg -encoders 2>/dev/null | grep nvv4l2
```

### インストール

```bash
git clone https://github.com/YOUR_USERNAME/jellyfin-nvv4l2-wrapper.git
cd jellyfin-nvv4l2-wrapper
sudo bash install.sh
sudo systemctl restart jellyfin
```

インストーラは以下を自動的に行います：
1. ラッパースクリプトを `/usr/local/bin/` にコピー
2. ffprobeフィルタリングを設定
3. `/etc/default/jellyfin` にFFmpegパスを設定（apt版のみ）

### 手動インストール

```bash
# スクリプトをコピー
sudo cp jellyfin-nvv4l2-wrapper /usr/local/bin/
sudo cp ffprobe-wrapper /usr/local/bin/
sudo chmod +x /usr/local/bin/jellyfin-nvv4l2-wrapper
sudo chmod +x /usr/local/bin/ffprobe-wrapper

# ffprobeシンボリックリンクを置換（NVMEDIA stdout汚染フィルタ）
sudo ln -sf /usr/local/bin/ffprobe-wrapper /usr/local/bin/ffprobe
```

JellyfinのFFmpegパスを設定（apt版）：

```bash
sudo nano /etc/default/jellyfin
```

`JELLYFIN_FFMPEG_OPT` の行を探し（存在しない場合は追加）、以下のように設定：

```bash
JELLYFIN_FFMPEG_OPT="--ffmpeg /usr/local/bin/jellyfin-nvv4l2-wrapper"
```

Jellyfinを再起動：

```bash
sudo systemctl restart jellyfin
```

> **注意**: 最新のJellyfinではWeb UIからFFmpegパスを直接編集できなくなっています。上記の `/etc/default/jellyfin` を編集する方法が必要です。この方法はapt版のJellyfinにのみ適用されます。

### アンインストール

```bash
cd jellyfin-nvv4l2-wrapper
sudo bash uninstall.sh
sudo systemctl restart jellyfin
```

### 動作確認

ラッパーのログを確認：

```bash
# 最新のffmpeg呼び出しと書き換え後の引数を表示
tail -20 /tmp/jellyfin-ffmpeg-wrapper.log
```

正常動作時は以下のように表示されます：
- `ARGS:` — Jellyfinからの元の引数 (`libx264` を含む)
- `NEW_ARGS:` — 書き換え後の引数 (`h264_nvv4l2` と `-hls_flags split_by_time` を含む)

ストリームコピー時（引数に `libx264`/`libx265` がない場合）：
- `NEW_ARGS(passthrough):` — 引数がそのまま渡されている

### 既知の制限事項

- **IDRフレーム制御不可**: `h264_nvv4l2` は `-g`, `-force_key_frames`, `-forced-idr` を無視します。`split_by_time` で回避していますが、シーク精度がやや低下する可能性があります。
- **ストリームコピーは無変更**: Jellyfinがトランスコードなしでリミックスする場合、ラッパーは全引数をそのまま通します。これは正常な動作です。
- **エンコード品質**: `-crf` を除去するため、`h264_nvv4l2` は内部デフォルトの品質設定を使用します。ビットレートはJellyfinの `-maxrate` と `-bufsize` パラメータで制御されます。
- **プロファイル/レベル**: ラッパーはJellyfinの `-profile` と `-level` フラグを保持しますが、`h264_nvv4l2` が全ての組み合わせをサポートするわけではありません（例：HighプロファイルがMainにフォールバックする場合あり）。
- **apt版のみ**: インストーラはapt版のJellyfinのみ対応しています。Docker版、Snap版、Flatpak版は未検証です。

### トラブルシューティング

| 症状 | 原因 | 対処法 |
|---|---|---|
| 再生が始まらない | セグメントが生成されていない可能性 | `/var/cache/jellyfin/transcodes/` を確認し、`/tmp/jellyfin-ffmpeg-wrapper.log` でエラーを確認 |
| Jellyfinログに `Error in Probe Provider` | NVMEDIAデバッグ出力がffprobeのJSONを破壊 | ffprobeシンボリックリンクが `ffprobe-wrapper` を指しているか確認 |
| エンコードは動いているがセグメントなし | `split_by_time` フラグが欠落 | ログの `NEW_ARGS` に `-hls_flags split_by_time` があるか確認 |
| 再生できるがシークが不正確 | `split_by_time` (IDRフレームなし) の想定される制限 | nvv4l2では正常な動作 |

## License

MIT License. See [LICENSE](LICENSE) for details.
