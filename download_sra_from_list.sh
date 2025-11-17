#!/usr/bin/env bash
set -euo pipefail
####################当前目录有：SraAccList.csv，只有一列 acc，内容类似：
#acc
#SRR10336412
#SRR10336415
#...


#################### 用户可修改参数 ####################
LIST_CSV="SraAccList.csv"    # 你的 SRA 列表
ACC_COL=1                    # acc 在 csv 的第几列（从 1 开始），这里是第一列
THREADS=8                    # fasterq-dump / pigz 线程数
OUT_SRA="sra"                # 存放 .sra 文件的目录
OUT_FASTQ="fastq"            # 存放 fastq(.gz) 的目录
MAX_SIZE="200G"              # prefetch 最大文件大小
COMPRESS_FASTQ=1             # 1=使用 pigz 压缩 fastq，0=不压缩
#################### 用户可修改参数 ####################

mkdir -p "${OUT_SRA}" "${OUT_FASTQ}"

# 从 CSV 中提取 accession 列（跳过表头）
ACC_LIST="acc.list"
cut -d',' -f${ACC_COL} "${LIST_CSV}" | tail -n +2 > "${ACC_LIST}"

echo "[INFO] Total accessions in ${ACC_LIST}: $(wc -l < ${ACC_LIST})"

while read -r ACC; do
    # 跳过空行
    if [[ -z "${ACC}" ]]; then
        continue
    fi

    # 如果 fastq 已经存在，就跳过（避免重复下载）
    if ls "${OUT_FASTQ}/${ACC}"_* 1>/dev/null 2>&1; then
        echo "[SKIP] ${ACC}: fastq already exists in ${OUT_FASTQ}"
        continue
    fi

    echo "==============================="
    echo "[INFO] Processing ${ACC}"

    # Step 1: prefetch 下载 .sra
    if [[ ! -s "${OUT_SRA}/${ACC}.sra" ]]; then
        echo "[INFO] prefetch ${ACC} ..."
        prefetch --max-size "${MAX_SIZE}" -O "${OUT_SRA}" "${ACC}"
    else
        echo "[INFO] ${OUT_SRA}/${ACC}.sra already exists, skip prefetch"
    fi

    # Step 2: fasterq-dump 转换为 fastq
    echo "[INFO] fasterq-dump ${ACC} ..."
    fasterq-dump \
        --split-files \
        --threads "${THREADS}" \
        -O "${OUT_FASTQ}" \
        "${OUT_SRA}/${ACC}.sra"

    # Step 3: 可选压缩 fastq
    if [[ "${COMPRESS_FASTQ}" -eq 1 ]]; then
        echo "[INFO] Compressing fastq for ${ACC} with pigz ..."
        pigz -p "${THREADS}" "${OUT_FASTQ}/${ACC}"_*.fastq
    fi

    echo "[DONE] ${ACC}"
    echo
done < "${ACC_LIST}"

echo "[ALL DONE] Download finished. Fastq in: ${OUT_FASTQ}, SRA in: ${OUT_SRA}"
