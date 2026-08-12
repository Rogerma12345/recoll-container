# 1. recoll-container

提供一个多架构 Docker 容器镜像（Docker container image）。同一镜像用于 Recoll 索引服务（Indexer）和网页界面（WebUI）。

`full-cpu` 分支在现有 Recoll、WebUI 和全部 Tesseract 语言数据基础上，增加本地 OpenAI Whisper 多语言语音转文字运行环境和 Aspell 英文词典。该分支发布独立的 `full-cpu` 镜像标签。

## 1.1 镜像内容

* Debian 13 trixie-slim
* Recoll 1.44.1 命令行索引器、查询工具和 Python 模块
* 固定提交 `127f849ae4bb4a690908ffef62cfb2d43784862d` 的 Recoll WebUI
* Waitress
* Tesseract 与 `tesseract-ocr-all`
* `rclimg.py` 所需的 Python exiv2 接口
* 常见 PDF、办公文档、邮件、图片和归档格式所需的自由软件处理组件
* OpenAI Whisper 20250625 多语言语音转文字运行环境
* Debian 中央处理器（Central Processing Unit，CPU）版 PyTorch
* FFmpeg
* Aspell、Aspell 运行库和 `aspell-en` 英文词典

`full-cpu` 不安装 CUDA、CUDA 版 PyTorch 或 Triton。Whisper 在该标签中按 CPU 运行。

Whisper 模型权重不写入镜像。

## 1.2 运行角色

`ROLE` 必须由部署端设置：

* `indexer`：按部署端设置的周期运行增量索引。
* `webui`：只运行 WebUI，不启动索引。
* `update-once`：运行一次 `recollindex`。
* `retry-once`：运行一次 `recollindex -k`。
* `reindex-in-place`：运行一次 `recollindex -Z`。

## 1.3 运行变量

所有角色都需要部署端设置：

* `ROLE`
* `PUID`
* `PGID`
* `TZ`

`RECOLL_CONFDIR` 使用固定容器路径 `/recoll/config`。

`indexer` 另外必须设置：

* `RECOLL_INDEX_RUN_ON_START`
* `RECOLL_INDEX_INTERVAL_SECONDS`

`full-cpu` 另外定义：

* `WHISPER_MODEL_DIR`：Whisper 模型目录，默认 `/recoll/models/whisper`。
* `WHISPER_ALLOW_DOWNLOAD`：是否允许 OpenAI Whisper 自动取得官方模型。默认 `0`。

`WHISPER_ALLOW_DOWNLOAD` 只有设置为 `1`、`true`、`yes` 或 `on` 时才允许自动取得模型。其他值均按禁止自动取得模型处理。

仓库不保存实际 UID、GID、时区、索引周期、启动策略、Whisper 模型型号或线程限制数值。

入口脚本在以 root 用户启动时，根据 `PUID` 和 `PGID` 降低运行权限。入口脚本不会修改绑定挂载的所有者或权限。

## 1.4 绑定挂载

镜像不声明 Docker `VOLUME`。部署目录由部署端预先建立，再通过绑定挂载（bind mount）加入容器。

Indexer：

* `/documents/source`：只读。
* `/recoll/config`：可写；部署端预先提供 `recoll.conf`、`mimeconf`、`missing`。
* `/recoll/index`：可写。
* `/recoll/cache`：可写。
* `/recoll/state`：可写；部署端预先提供 `idxstatus.txt`。
* `/recoll/tmp`：可写。
* `/recoll/models/whisper`：Whisper 模型目录。禁止自动取得模型时可以只读挂载；允许自动取得模型时必须可写。

WebUI：

* `/documents/source`：只读。
* `/recoll/config`：只读。
* `/recoll/index`：只读。
* `/recoll/cache`：可写；使用 WebUI 独立缓存目录。
* `/recoll/tmp`：可写；使用 WebUI 独立临时目录。
* `/recoll/models/whisper`：Whisper 模型目录。可以与 Indexer 使用同一个只读模型目录；允许 WebUI 自动取得模型时必须可写。
* `/recoll/state`：不挂载。

入口脚本不会建立绑定源目录，不会改变绑定源的所有者或权限，也不会生成 `recoll.conf`、`mimeconf`、`missing`、`idxstatus.txt` 或 Whisper 模型。部署端需要确保所设置的 `PUID` 和 `PGID` 对相应挂载具备所需权限。

## 1.5 Recoll 配置

仓库不提供私有 `recoll.conf` 或 `mimeconf` 模板。部署端配置使用固定容器路径：

* 资料源：`/documents/source`
* 索引：`/recoll/index`
* 缓存：`/recoll/cache`
* 状态文件：`/recoll/state/idxstatus.txt`
* 临时目录：`/recoll/tmp`
* Whisper 模型：`/recoll/models/whisper`

`dbdir`、`ocrcachedir`、`mboxcachedir` 和 `idxstatusfile` 应设置到对应的独立挂载位置。

实际资料目录规则、排除规则、仅文件名规则、OCR 参数、语音转文字参数和索引周期均保存在部署端。

## 1.6 光学字符处理

镜像安装光学字符处理（Optical Character Recognition，OCR）程序 Tesseract 以及 `tesseract-ocr-all`，构建阶段安装 Debian 当前提供的全部 Tesseract 语言和文字系统数据。

`full-cpu` 不改变 Tesseract 软件包、语言数据安装方式或现有 OCR 处理程序。

实际 `tesseractlang`、`imgocr`、`pdfocr` 和按目录设置的 OCR 规则均由部署端 `recoll.conf` 决定。

Linux 系统（Linux）的图片 OCR 可以在部署端 `mimeconf` 中把需要处理的媒体类型（MIME）设置为 `execm rclimg.py`。

## 1.7 语音转文字

`full-cpu` 提供 Recoll 1.44.1 使用 OpenAI Whisper 所需的本地语音转文字（Speech-to-Text，STT）运行组件，包括 CPU PyTorch、FFmpeg、NumPy、Numba、tiktoken、tqdm 和其他运行依赖。

Recoll 通过 `speechtotext = whisper` 启用该功能。模型型号由部署端 `sttmodel` 设置，运行设备由部署端 `sttdevice` 设置。

Whisper 的 `tiny`、`base`、`small`、`medium`、`large` 和 `turbo` 可以处理多语言语音转写。带 `.en` 后缀的对应型号只用于英文。镜像不固定部署端使用的模型型号。

镜像不包含任何 Whisper `.pt` 权重。默认模型目录为 `/recoll/models/whisper`。

对于按官方模型名称加载的权重，镜像保留 OpenAI Whisper 的安全散列算法 256（Secure Hash Algorithm 256，SHA-256）校验规则。模型目录中已有官方文件且校验正确时，使用本地文件。

模型不存在或校验失败，同时 `WHISPER_ALLOW_DOWNLOAD=0` 时，该次模型加载失败并输出模型路径，不发起模型下载。

显式允许 `WHISPER_ALLOW_DOWNLOAD` 后，模型先保存为模型目录中的临时文件。下载完成并通过 SHA-256 校验后，再替换正式模型文件。并行进程使用文件锁避免同时写入同一官方模型文件。

Recoll 的语音转写结果使用与 OCR 相同的缓存机制。模型权重目录和转写结果缓存属于不同目录。

## 1.8 拼写建议

`full-cpu` 安装 Aspell 和 `aspell-en`。Recoll 使用英文 Aspell 词典时具备词典生成所需的运行数据。

其他 Aspell 语言词典没有随镜像安装。部署端不需要拼写建议时，可以通过 Recoll 配置关闭 Aspell。

构建和发布测试都会实际创建一次临时英文 Aspell 主词典，以检查语言数据是否可用。

## 1.9 WebUI

WebUI 使用固定容器端口 `8080`，通过 Waitress 运行，只查询部署端提供的 Recoll 配置和索引。

预览（Preview）和下载（Download）会使用 Recoll 文档提取接口，因此 WebUI 使用可写的独立缓存目录和临时目录。认证和反向代理不包含在本仓库中。

`full-cpu` 的 WebUI 进程也具备 Whisper 运行环境。WebUI 在文档提取阶段需要语音转写时，使用同一套模型目录规则和模型下载策略。

## 1.10 镜像标签

`full-cpu` 分支由独立 GitHub 自动构建（GitHub Actions）工作流发布：

* `full-cpu`

该工作流不发布 `edge`、`latest` 或版本号标签。

`main` 分支的原发布规则保持独立：

* 手工运行原 GitHub Actions：发布 `edge`。
* 推送 `vX.Y.Z` Git 标签：发布 `X.Y.Z`、`X.Y` 和 `latest`。

镜像发布平台：

* `linux/amd64`
* `linux/arm64`

## 1.11 测试职责

`full-cpu` 的 GitHub Actions 在发布前分别使用 AMD64 和 ARM64 GitHub 托管运行器构建并测试镜像。

构建阶段检查 Recoll 1.44.1、`tesseract-ocr-all`、Aspell 英文词典、FFmpeg、CPU PyTorch、OpenAI Whisper 20250625、NumPy、Numba、tiktoken、tqdm 和 Recoll 音频处理程序。

两个平台都使用官方 `tiny` 多语言模型执行一次真实 CPU 音频转写。测试容器关闭网络，模型通过只读挂载提供，因此测试可以检查本地模型加载和 CPU 推理链路。

持续集成（Continuous Integration，CI）使用的 Whisper 权重只存在于测试作业目录，不写入发布镜像。

构建还检查镜像内 `/recoll/models/whisper` 没有任何模型权重。

索引、OCR、WebUI、Preview、Download、认证和部署端绑定挂载权限仍由部署环境负责测试。

## 1.12 上游和许可证

仓库固定使用 Recoll 1.44.1 和 Recoll WebUI 提交 `127f849ae4bb4a690908ffef62cfb2d43784862d`。

`full-cpu` 固定使用 OpenAI Whisper 20250625。Whisper 代码和官方模型继续遵守其上游 MIT 许可证。

本仓库自己的 Docker 封装、入口脚本和新增 Whisper 策略代码使用 `LICENSE` 中的 MIT 许可证。镜像内 Recoll、Recoll WebUI、Debian 和其他第三方组件继续遵守各自上游许可证。
