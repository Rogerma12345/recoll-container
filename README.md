# 1. recoll-container

提供一个多架构 Docker 容器镜像（Docker container image）。同一镜像用于 Recoll 索引服务（Indexer）和网页界面（WebUI）。

## 1.1 镜像内容

* Debian 13 trixie-slim
* Recoll 1.44.1 命令行索引器、查询工具和 Python 模块
* 固定提交 `127f849ae4bb4a690908ffef62cfb2d43784862d` 的 Recoll WebUI
* Waitress
* Tesseract 与 `tesseract-ocr-all`
* `rclimg.py` 所需的 Python exiv2 接口
* Aspell 主程序和运行库；`main` 当前不安装 Aspell 语言词典
* 常见 PDF、办公文档、邮件、图片和归档格式所需的自由软件处理组件

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

仓库不保存实际 UID、GID、时区、索引周期或启动策略数值。

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

WebUI：

* `/documents/source`：只读。
* `/recoll/config`：只读。
* `/recoll/index`：只读。
* `/recoll/cache`：可写；使用 WebUI 独立缓存目录。
* `/recoll/tmp`：可写；使用 WebUI 独立临时目录。
* `/recoll/state`：不挂载。

入口脚本不会建立绑定源目录，不会改变绑定源的所有者或权限，也不会生成 `recoll.conf`、`mimeconf`、`missing` 或 `idxstatus.txt`。部署端需要确保所设置的 `PUID` 和 `PGID` 对相应挂载具备所需权限。

## 1.5 Recoll 配置

仓库不提供私有 `recoll.conf` 或 `mimeconf` 模板。部署端配置使用固定容器路径：

* 资料源：`/documents/source`
* 索引：`/recoll/index`
* 缓存：`/recoll/cache`
* 状态文件：`/recoll/state/idxstatus.txt`
* 临时目录：`/recoll/tmp`

`dbdir`、`ocrcachedir`、`mboxcachedir` 和 `idxstatusfile` 应设置到对应的独立挂载位置。

实际资料目录规则、排除规则、仅文件名规则、OCR 参数和索引周期均保存在部署端。

## 1.6 光学字符处理

镜像安装光学字符处理（Optical Character Recognition，OCR）程序 Tesseract 以及 `tesseract-ocr-all`，构建阶段安装 Debian 当前提供的全部 Tesseract 语言和文字系统数据。

实际 `tesseractlang`、`imgocr`、`pdfocr` 和按目录设置的 OCR 规则均由部署端 `recoll.conf` 决定。

Linux 系统（Linux）的图片 OCR 可以在部署端 `mimeconf` 中把需要处理的媒体类型（MIME）设置为 `execm rclimg.py`。

## 1.7 可选功能状态

`main` 分支及其 `edge`、版本号和 `latest` 镜像当前安装 Aspell 主程序和运行库，但 Dockerfile 没有安装 `aspell-en` 等 Aspell 语言词典。因此 `main` 不保证 Recoll 拼写建议词典可以建立。

`main` 当前 Dockerfile 没有把 OpenAI Whisper、PyTorch 和 FFmpeg 作为语音转文字运行组件安装，因此不把 Recoll 的 `speechtotext = whisper` 列为该镜像保证的功能。

`full-cpu` 分支和 `full-cpu` 镜像标签增加 CPU OpenAI Whisper 多语言语音转文字运行环境以及 `aspell-en` 英文词典。

`full-cpu` 继续安装 `tesseract-ocr-all`。PDF OCR、图片 OCR 和全部 Debian Tesseract 语言数据的安装方式与 `main` 保持相同。

`full-cpu` 不把 Whisper 模型权重写入镜像，并使用独立模型目录管理本地权重。

## 1.8 WebUI

WebUI 使用固定容器端口 `8080`，通过 Waitress 运行，只查询部署端提供的 Recoll 配置和索引。

预览（Preview）和下载（Download）会使用 Recoll 文档提取接口，因此 WebUI 使用可写的独立缓存目录和临时目录。认证和反向代理不包含在本仓库中。

## 1.9 镜像标签

`main` 分支：

* 手工运行 GitHub 自动构建（GitHub Actions）：发布 `edge`。
* 推送 `vX.Y.Z` Git 标签：发布 `X.Y.Z`、`X.Y` 和 `latest`。

`full-cpu` 分支：

* 独立工作流发布 `full-cpu`。
* `full-cpu` 提供 CPU OpenAI Whisper 多语言语音转文字环境和 Aspell 英文词典，同时保持 `tesseract-ocr-all`。

镜像发布平台：

* `linux/amd64`
* `linux/arm64`

## 1.10 测试职责

`main` 的 GitHub Actions 负责多架构构建、镜像内基础软件检查和 GitHub 容器注册表（GitHub Container Registry，GHCR）发布。

索引、OCR、WebUI、Preview、Download、认证及实际绑定挂载权限由部署端拉取已发布镜像后进行本机测试。

`full-cpu` 使用独立工作流，在发布前额外执行 AMD64、ARM64 的 Whisper CPU 实际转写测试和 Aspell 英文词典创建测试。

## 1.11 上游和许可证

仓库固定使用 Recoll 1.44.1 和 Recoll WebUI 提交 `127f849ae4bb4a690908ffef62cfb2d43784862d`。

本仓库自己的 Docker 封装和入口脚本使用 `LICENSE` 中的 MIT 许可证。镜像内 Recoll、Recoll WebUI、Debian 和其他第三方组件继续遵守各自上游许可证。
