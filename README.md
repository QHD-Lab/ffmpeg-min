# ffmpeg-min

Minimal LGPL-2.1 FFmpeg builds (AAC/AC-3/MP2 decode, Opus encode, RTSP) for iCrew.

This software uses code of [FFmpeg](https://ffmpeg.org) licensed under the
[LGPLv2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html), and its source can be downloaded from the
[Releases](https://github.com/QHD-Lab/ffmpeg-min/releases) page, next to each binary.

## 用途

iCrew 把切换台的 PGM 经 mediamtx 发给手机。手机和浏览器的 WebRTC 只能播 Opus，编码器多半推 AAC，所以 iCrew 起一个 ffmpeg 子进程：
从本机 RTSP 读 `pgm-in`，视频原样复制，音频转成 Opus，再发布到 `pgm-out`。这个仓库只做这一个 ffmpeg，别的功能一律不编进去。

| 有 | 没有 |
|---|---|
| RTSP 收发（rtsp、rtp、sdp，tcp、udp、rtp 协议） | 任何视频编码器、视频解码器、swscale |
| H.264、H.265 parser 和视频 copy 用的 bsf | GPL、nonfree、version3 组件 |
| 音频解码 aac、aac_latm、ac3、eac3、mp1、mp2、mp3 | 自动探测到的系统库（`--disable-autodetect`） |
| 音频编码只有 libopus；aresample、aformat 等滤镜 | ffprobe、ffplay、libavdevice |

完整的 configure 行在 [scripts/lib.sh](scripts/lib.sh)，每个 Release 里也有各平台的 `ffmpeg-<平台>.configure.txt`，
和 `ffmpeg -buildconf` 输出一致。

## 版本与平台

源码版本和 sha256 钉在 [versions.env](versions.env)：FFmpeg 9.0.2、libopus 1.6.1，都用官方源码包，不打补丁。

| 平台 | 构建方式 | 链接 |
|---|---|---|
| linux-amd64、linux-arm64 | 各自的 Linux 机器上用 gcc 编 | 全静态 |
| darwin-amd64、darwin-arm64 | 各自的 Mac 上用 clang 编，最低 macOS 11 | 只静态链 libopus，系统库动态 |
| windows-amd64 | Linux 上用 mingw-w64 交叉编译 | 全静态，只依赖 Windows 自带 DLL |

## 许可

- 构建脚本（本仓库的文件）：MIT，见 [LICENSE](LICENSE)。
- 二进制：FFmpeg 按 LGPL 2.1 或更高版本授权，`ffmpeg -L` 会显示；里面静态链入的 libopus 按 BSD 式许可。
- 每个 Release 里同时放着：五个二进制和各自的 `.sha256`、对应的 FFmpeg 和 libopus 原始源码包、构建脚本包、
  各平台 configure 行、`COPYING.LGPLv2.1`、`LICENSE-opus.txt`、`SHA256SUMS`。

按 [FFmpeg 法律页](https://ffmpeg.org/legal.html) 的要求：不用 `--enable-gpl`、`--enable-nonfree`；
源码和二进制放在同一处（同一个 GitHub Release）；没有修改 FFmpeg 源码；程序名保持 `ffmpeg`；
分发方要在自己的许可页说明使用了 FFmpeg（上面那句英文即可）、不声称拥有 FFmpeg，也不得禁止用户逆向或修改它。
这是独立的可执行文件，iCrew 只通过命令行参数和 RTSP 套接字跟它交互，不链接它的库。

专利：FFmpeg 不评估专利问题，本仓库也不。AAC、AC-3 等格式在某些地区可能涉及专利许可，请自行判断。

## 自己重建和替换

需要 bash、curl、make、pkg-config 和 C 编译器（Linux 用 gcc，macOS 用 Xcode 命令行工具，Windows 版在 Linux 上装 `gcc-mingw-w64-x86-64`）。

```sh
./scripts/build-linux-arm64.sh        # 平台对应的入口，一个平台一个
./scripts/smoke.sh out/ffmpeg-linux-arm64
```

脚本下载 `versions.env` 里的源码包并核对 sha256，结果在 `out/`：二进制、`.sha256`、`.configure.txt`。
想改 FFmpeg（比如加补丁或换版本），把改好的源码打成 `.tar.xz`，在 `versions.env` 里改 URL（本地文件可写 `file:///…`）和 sha256，删掉 `build/dl` 里的旧包后重编。

替换 iCrew 里的 ffmpeg：用环境变量 `ICREW_FFMPEG=<你的 ffmpeg 的绝对路径>` 启动 iCrew 服务，
或者替换安装目录 `server/` 下的 `ffmpeg`（Windows 是 `ffmpeg.exe`）。macOS 的 App 签名后改包内文件会破坏签名，请用环境变量指向包外的文件。

## 冒烟测试

[scripts/smoke.sh](scripts/smoke.sh) 只用被测的这个二进制，不需要别的软件：

1. `-buildconf` 里没有 gpl、nonfree、version3，`-L` 是 LGPL 2.1；
2. 编码器只有 libopus，需要的解码器、RTSP、协议都在；
3. AC-3 和 MP2 样本转 Opus；
4. 在 127.0.0.1 上跑一遍 iCrew 的实际链路：推 H.264+AAC 样本 → 一个 ffmpeg 收、视频 copy、音频转 Opus、再推出去 → 另一个 ffmpeg 收，检查是 H264 + Opus 48 kHz 立体声且帧数够。

样本在 `test/fixtures`，是用 [test/make-fixtures.sh](test/make-fixtures.sh) 生成的测试图案和正弦音。

## CI 和发版

[.github/workflows/build.yml](.github/workflows/build.yml) 只用 GitHub 托管的 runner。PR 和手动触发时编五个平台、检查链接的库、
跑冒烟测试（Windows 版在 Windows runner 上跑），产物作为 artifact 上传。推 `v*` tag 时再把上面列的文件放进同一个 Release；
tag 带 `-`（如 `v1.0.0-beta.1`）的标为 prerelease。
