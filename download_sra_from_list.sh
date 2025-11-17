#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------
# Script Name / 脚本名称: download_sra_from_list.sh
#
# 说明：
#  - 适配 SRA Toolkit 3.x 的目录结构：
#      prefetch -O sra ERR1760143
#      → sra/ERR1760143/ERR1760143.sra
#  - fasterq-dump 直接读取该 .sra 文件路径
#  - 自动跳过已生成的 FASTQ，支持重复运行
# -------------------------------------------------------------

#################### 用户可修改参数 ####################

# SRA 列表文件（第一行是表头）
# 注意：根据你的实际文件名修改，例如：
# LIST_CSV="Cp_SraAccList.csv"
LIST_CSV="Cp_SraAccList.csv"

# SRA accession 在 CSV 中的列号（从 1 开始）
ACC_COL=1

# 线程数（用于 fasterq-dump 和 pigz）
THREADS=8

# 存放 .sra 的目录（prefetch 输出目录）
OUT_SRA="sra"

# 存放 fastq / fastq.gz 的目录
OUT_FASTQ="fastq"

# prefetch 最大允许文件大小（可根据需要调整）
MAX_SIZE="200G"

# 是否压缩 fastq（1=使用 pigz 压缩为 .gz，0=不压缩）
COMPRESS_FASTQ=1

#################### 用户可修改参数 ####################

mkdir -p "${OUT_SRA}" "${OUT_FASTQ}"

ACC_LIST="acc.list"

# 从 CSV 提取 accession 列，跳过表头
# 若你的文件是制表符分隔，请将 -d',' 改为 -d$'\t'
cut -d',' -f${ACC_COL} "${LIST_CSV}" | tail -n +2 > "${ACC_LIST}"

TOTAL=$(wc -l < "${ACC_LIST}")
echo "[INFO] Total accessions in ${ACC_LIST}: ${TOTAL}"

while read -r ACC; do
    # 跳过空行
    if [[ -z "${ACC}" ]]; then
        continue
    fi

    # 如果 fastq 或 fastq.gz 已存在，说明已完成，直接跳过
    if ls "${OUT_FASTQ}/${ACC}"_*.fastq* 1>/dev/null 2>&1; then
        echo "[SKIP] ${ACC}: FASTQ already exists in ${OUT_FASTQ}"
        continue
    fi

    echo "==============================="
    echo "[INFO] Processing ${ACC}"

    # 预期的 .sra 路径：sra/ACC/ACC.sra
    SRA_PATH="${OUT_SRA}/${ACC}/${ACC}.sra"

    # 若该路径不存在，则先执行 prefetch
    if [[ ! -f "${SRA_PATH}" ]]; then
        echo "[INFO] ${SRA_PATH} not found, running prefetch ..."
        if ! prefetch --max-size "${MAX_SIZE}" -O "${OUT_SRA}" "${ACC}"; then
            echo "[ERROR] prefetch failed for ${ACC}, skip this accession." >&2
            continue
        fi
    else
        echo "[INFO] SRA file already exists: ${SRA_PATH}, skip prefetch"
    fi

    # 再次检查 .sra 是否存在
    if [[ ! -f "${SRA_PATH}" ]]; then
        echo "[ERROR] Cannot find SRA file for ${ACC} at ${SRA_PATH}, skip." >&2
        continue
    fi

    echo "[INFO] Using SRA file: ${SRA_PATH}"

    # Step 2: fasterq-dump 转换为 fastq
    echo "[INFO] fasterq-dump ${ACC} ..."
    if ! fasterq-dump \
        --split-files \
        --threads "${THREADS}" \
        -O "${OUT_FASTQ}" \
        "${SRA_PATH}"; then
        echo "[ERROR] fasterq-dump failed for ${ACC}, skip compression." >&2
        continue
    fi

    # Step 3: 可选压缩 fastq -> fastq.gz
    if [[ "${COMPRESS_FASTQ}" -eq 1 ]]; then
        echo "[INFO] Compressing FASTQ for ${ACC} with pigz ..."
        if ls "${OUT_FASTQ}/${ACC}"_*.fastq 1>/dev/null 2>&1; then
            pigz -p "${THREADS}" "${OUT_FASTQ}/${ACC}"_*.fastq
        else
            echo "[WARN] No FASTQ files found for ${ACC} to compress." >&2
        fi
    fi

    echo "[DONE] ${ACC}"
    echo
done < "${ACC_LIST}"

echo "[ALL DONE] Download finished. FASTQ in: ${OUT_FASTQ}, SRA in: ${OUT_SRA}"
