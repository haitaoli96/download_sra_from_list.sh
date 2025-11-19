# Workflow: Batch Download of SRA Data and Metadata Integration

本文件说明如何结合 `download_sra_from_list.sh` 与 `fetch_sra_metadata.py`，完成 **NCBI SRA 原始数据批量下载 + 元数据信息汇总** 的完整流程，便于他人开箱即用。

---

## 1. 目标与整体思路

目标：

1. 根据 SRA 登录号列表（如 `Cp_SraAccList.csv`）批量下载所有对应的 `.fastq(.gz)` 文件；
2. 同时获取这些 run 的关键信息（如 `SRA, BioSample, strain, host, collection_date, geographic_location, sample_type, Submission`），整理为一个统一的 metadata 表格，类似：

```text
SRA          strain      host          collection_date  geographic_location  sample_type  Submission
SRR10336412  IIaA15G2R1  Bos taurus    2008-05-07       USA: Iowa            missing      Center for Disease Control and Prevention
SRR10336415  IIaA15G2R1  Bos taurus    missing          USA: Iowa            missing      Center for Disease Control and Prevention
...
```

整体流程：

1. 准备包含 SRA 登录号的 CSV：`Cp_SraAccList.csv`
2. 使用 `download_sra_from_list.sh` 批量下载 `.sra → fastq(.gz)`；
3. 使用 `fetch_sra_metadata.py` 从 NCBI/ENA 拉取每个 SRA 的 metadata；
4. （可选）只保留下载成功的 SRA，生成最终可用于分析的 metadata 表。

---

## 2. 目录结构与文件说明

推荐的项目结构如下（示例）：

```text
project_root/
│
├── Cp_SraAccList.csv          # 输入：包含 SRA 登录号的一张表（至少有 acc 列）
├── download_sra_from_list.sh  # 脚本 1：批量下载 SRA → fastq
├── fetch_sra_metadata.py      # 脚本 2：批量抓取 SRA metadata
│
├── acc.list                   # download 脚本自动生成的纯 accession 列表
├── download_status.tsv        # download 脚本生成：记录每个 SRA 的下载状态
│
├── sra/                       # 存放 prefetch 下载的 .sra 文件
├── fastq/                     # 存放 fasterq-dump 输出的 fastq / fastq.gz
│
├── SRA_metadata_raw.tsv       # fetch_sra_metadata.py 输出：所有 SRA 的原始 metadata 表
└── SRA_metadata_merged.tsv    # （推荐）与下载状态合并筛选后的最终 metadata 表
```

> 具体文件名可根据你仓库中的实际命名略有不同，请在 README 中保持一致即可。

---

## 3. 前置条件与依赖

### 3.1 软件依赖

- Bash（Linux / macOS 终端环境）
- Python 3（建议 ≥3.8）
- NCBI SRA Toolkit（用于 `prefetch` + `fasterq-dump`）
- 建议安装：
  - `pigz`（多线程压缩 fastq，可选）
  - Python 包：`requests`, `pandas`（取决于 `fetch_sra_metadata.py` 实现）

示例（conda 安装环境）：

```bash
# 安装 sra-tools 和 pigz
conda install -c bioconda sra-tools pigz

# 安装 Python 依赖
pip install requests pandas
```

### 3.2 输入文件格式：`Cp_SraAccList.csv`

要求至少包含一列 `acc`，内容为 SRA 登录号（SRR/ERR 等），例如：

```csv
acc,strain,host,other_info
SRR10336412,IIaA15G2R1,Bos taurus,...
SRR10336415,IIaA15G2R1,Bos taurus,...
SRR10336414,IIaA15G2R1,Bos taurus,...
```

`download_sra_from_list.sh` 默认从该文件中提取 `acc` 列。

---

## 4. 脚本 1：`download_sra_from_list.sh` 使用说明

`download_sra_from_list.sh` 的主要功能：

1. 从 `Cp_SraAccList.csv` 提取所有 SRA accession（acc 列）；
2. 使用 `prefetch` 下载每个 accession 的 `.sra`：
   - 默认输出到 `sra/ACC/ACC.sra`；
3. 使用 `fasterq-dump` 将 `.sra` 转换为 `fastq`：
   - 默认输出到 `fastq/ACC_1.fastq(.gz)` 与 `fastq/ACC_2.fastq(.gz)`；
4. 支持：
   - 自动跳过已存在的 FASTQ；
   - 自动记录下载状态到 `download_status.tsv`；
   - 可断点续跑、多进程并行。

### 4.1 关键参数（脚本顶部配置）

在脚本开头，你通常会看到类似配置段（示意）：

```bash
LIST_CSV="Cp_SraAccList.csv"  # 输入 CSV
ACC_COL=1                     # acc 列在 CSV 中的列号（从 1 开始）
THREADS=8                     # fasterq-dump 与 pigz 使用的线程数
OUT_SRA="sra"                 # .sra 存储目录
OUT_FASTQ="fastq"             # fastq 存储目录
MAX_SIZE="200G"               # prefetch 允许的最大文件大小
COMPRESS_FASTQ=1              # 是否使用 pigz 压缩 fastq
```

根据自己实际情况修改：

- 如果 `acc` 不在第一列（例如在第 2 列），需要把 `ACC_COL=1` 改成 `ACC_COL=2`；
- 调整 `THREADS` 以匹配你服务器的 CPU 核心数；
- 如果不想压缩 fastq，可将 `COMPRESS_FASTQ=0`。

### 4.2 运行下载脚本

在项目目录下执行：

```bash
chmod +x download_sra_from_list.sh
bash download_sra_from_list.sh
```

脚本会：

- 生成 `acc.list`：纯 accession 列表；
- 对每个 SRA 进行下载与转换；
- 将 `.sra` 存储到 `sra/`，`fastq(.gz)` 存储到 `fastq/`；
- 将下载状态记录到 `download_status.tsv`，格式类似：

```text
SRA           status              message
SRR10336412   DUMP_OK             FASTQ generated successfully.
SRR10336415   PREFETCH_FAIL       prefetch failed.
SRR10336414   SKIP_FASTQ_EXISTS   FASTQ already exists, skipped.
...
```

> **可反复运行**：脚本会自动跳过已下载完成的样本，非常适合断点续跑或多进程并行。

---

## 5. 脚本 2：`fetch_sra_metadata.py` 使用说明

`fetch_sra_metadata.py` 用于从 NCBI/ENA API 批量获取每个 SRA 的运行信息（RunInfo），并整理为可直接用于分析的 metadata 表。

典型输出字段包括（实际视脚本实现）：

- `SRA`（Run accession）
- `BioSample`
- `strain`
- `host`
- `collection_date`
- `geographic_location`
- `sample_type`
- `Submission`
- （以及其他 NCBI RunInfo 中可用字段）

### 5.1 输入与输出

常见实现方式是：

- 输入：
  - `Cp_SraAccList.csv`（至少包含 `acc` 列）
  - （可选）`download_status.tsv`（用来只保留下载成功的样本）
- 输出：
  - `SRA_metadata_raw.tsv`：所有样本的 metadata
  - `SRA_metadata_merged.tsv`：与下载状态合并后，仅保留成功下载样本的 metadata

请在 README 中说明脚本的实际参数，如果你实现的是“**零参数版本**”，则通常只需要：

```bash
python3 fetch_sra_metadata.py
```

示例说明可以写成：

```bash
# 方式 1：默认从 Cp_SraAccList.csv 中读取 acc，输出到 SRA_metadata_raw.tsv
python3 fetch_sra_metadata.py

# 方式 2（如果脚本支持参数）：指定输入/输出文件
python3 fetch_sra_metadata.py   --input Cp_SraAccList.csv   --status download_status.tsv   --output SRA_metadata_merged.tsv
```

### 5.2 常见脚本逻辑示意（便于他人理解）

README 中可以用文字说明脚本大致行为，例如：

1. 读取 `Cp_SraAccList.csv` 中的 `acc` 列，得到所有 SRA accession；
2. 对每个 accession 调用 NCBI/ENA 的 API 或下载 `RunInfo`；
3. 从 RunInfo 中提取 BioSample, host, strain, collection_date 等字段；
4. 整理成统一的表格 `SRA_metadata_raw.tsv`；
5. （可选）读取 `download_status.tsv`，仅保留 `status == "DUMP_OK"` 的样本，生成 `SRA_metadata_merged.tsv`。

这样即便其他人没有仔细读代码，也能理解脚本的设计思路。

---

## 6. 推荐的标准流程（供用户复制）

可以在 README 里提供一个“完整流程一览”，例如：

```bash
# 1. 准备好 Cp_SraAccList.csv（包含 acc 列）

# 2. 批量下载 SRA → fastq(.gz)
bash download_sra_from_list.sh

# 3. 获取 SRA 对应的 metadata 信息
python3 fetch_sra_metadata.py

# 4. 查看结果：
#    - fastq/                    # 原始序列文件
#    - download_status.tsv       # 每个样本的下载状态
#    - SRA_metadata_raw.tsv      # 全部样本 metadata
#    - SRA_metadata_merged.tsv   # （可选）仅成功下载样本的 metadata
```

---

## 7. 常见问题（FAQ）

### Q1：脚本能否重复运行？会不会重复下载？

**不会。**  
`download_sra_from_list.sh` 会检查 `fastq/ACC_*.fastq*` 是否已存在：

- 若存在：直接跳过该样本（状态为 `SKIP_FASTQ_EXISTS`）；
- 若不存在：执行 prefetch + fasterq-dump。

因此可以安全：

- 多次运行同一个脚本；
- 中途 Ctrl+C 停止后，重新跑脚本继续下载未完成的部分。

### Q2：如何只保留“下载成功”的样本 metadata？

在 `fetch_sra_metadata.py` 中，建议：

- 读取 `download_status.tsv`；
- 只保留 `status == "DUMP_OK"` 的 SRA；
- 将结果输出为 `SRA_metadata_merged.tsv`。

如果你已经实现了这一功能，请在 README 中给出明确示例命令。

### Q3：metadata 中有 `missing` 的字段怎么办？

部分 Run 的 `collection_date`、`sample_type` 在 NCBI 中本身就缺失（未填写）：

- 可以在脚本中将空值统一替换为 `missing` 或 `NA`；
- 在 README 中说明这是数据源本身的限制，不是脚本错误。

---

## 8. 致贡献者

欢迎：

- 提交 issue 报告 bug 或提出新需求；
- 提交 PR 改进脚本的鲁棒性（如 API 重试、并发请求、缓存机制）；
- 扩展 `fetch_sra_metadata.py` 支持更多字段或更多数据库（ENA/EBI 等）。

---

如果你正在进行 Cryptosporidium / Giardia / Toxoplasma 等寄生虫的群体基因组学研究，本项目可以作为批量数据获取与样本信息整理的标准组件，方便与后续比对、变异检测和群体遗传分析流程对接。
