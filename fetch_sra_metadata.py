#!/usr/bin/env python3
import csv
import time
import os
import glob
import sys
import requests
import xml.etree.ElementTree as ET

#################### 用户可修改参数 ####################
LIST_CSV = "SraAccList.csv"       # SRA 列表（含列 acc）
ACC_COL_NAME = "acc"              # SRA 列名
FASTQ_DIR = "fastq"               # fastq 所在目录（与下载脚本一致）
OUT_TSV = "sra_metadata_summary.tsv"
NCBI_EMAIL = "your_email@example.com"  # 建议填上你的邮箱，符合 NCBI 要求
SLEEP_SEC = 0.4                   # 请求间隔，避免压垮 NCBI（~2.5 req/s）
#################### 用户可修改参数 ####################

EUTILS_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"


def load_accessions(csv_file, col_name):
    accs = []
    with open(csv_file, newline='') as f:
        reader = csv.DictReader(f)
        if col_name not in reader.fieldnames:
            raise ValueError(f"列 {col_name} 不在 {csv_file} 中，实际列名: {reader.fieldnames}")
        for row in reader:
            acc = row[col_name].strip()
            if acc:
                accs.append(acc)
    return accs


def has_fastq(acc, fastq_dir):
    """判断该样本是否已经下载（fastq 或 fastq.gz 是否存在）"""
    pattern1 = os.path.join(fastq_dir, f"{acc}_*.fastq")
    pattern2 = os.path.join(fastq_dir, f"{acc}_*.fastq.gz")
    files = glob.glob(pattern1) + glob.glob(pattern2)
    return len(files) > 0


def fetch_sra_xml(acc):
    """从 NCBI E-utilities 获取 SRA XML"""
    params = {
        "db": "sra",
        "id": acc,
        "retmode": "xml",
        "email": NCBI_EMAIL
    }
    r = requests.get(EUTILS_URL, params=params, timeout=60)
    r.raise_for_status()
    return r.text


def parse_metadata_from_xml(xml_text, fallback_acc):
    """
    解析单个 SRA run 的元数据。
    返回 dict：{SRA, strain, host, collection_date, geographic_location, sample_type, Submission}
    """
    root = ET.fromstring(xml_text)

    # SRA XML 结构一般：EXPERIMENT_PACKAGE_SET / EXPERIMENT_PACKAGE
    pkg = root.find(".//EXPERIMENT_PACKAGE")
    if pkg is None:
        # 非常极端的情况
        return {
            "SRA": fallback_acc,
            "strain": "missing",
            "host": "missing",
            "collection_date": "missing",
            "geographic_location": "missing",
            "sample_type": "missing",
            "Submission": "missing",
        }

    # SRA accession
    run = pkg.find(".//RUN")
    if run is not None and "accession" in run.attrib:
        sra = run.attrib["accession"]
    else:
        sra = fallback_acc

    # SUBMITTER center_name -> Submission
    submitter = pkg.find(".//SUBMITTER")
    submission = submitter.get("center_name", "missing") if submitter is not None else "missing"

    # SAMPLE_ATTRIBUTE 里的 tag / value
    attrs = {}
    for attr in pkg.findall(".//SAMPLE_ATTRIBUTE"):
        tag = attr.findtext("TAG", default="").strip().lower()
        val = attr.findtext("VALUE", default="").strip()
        if tag:
            attrs[tag] = val

    # 依次尝试从不同 tag 中拿值
    strain = attrs.get("strain") or attrs.get("isolate") or "missing"
    host = attrs.get("host") or "missing"
    collection_date = attrs.get("collection_date") or "missing"
    geo = (
        attrs.get("geographic location") or
        attrs.get("geo_loc_name") or
        attrs.get("geolocation") or
        "missing"
    )
    sample_type = (
        attrs.get("sample_type") or
        attrs.get("isolation_source") or
        attrs.get("sample type") or
        "missing"
    )

    return {
        "SRA": sra,
        "strain": strain if strain else "missing",
        "host": host if host else "missing",
        "collection_date": collection_date if collection_date else "missing",
        "geographic_location": geo if geo else "missing",
        "sample_type": sample_type if sample_type else "missing",
        "Submission": submission if submission else "missing",
    }


def main():
    if not os.path.exists(LIST_CSV):
        print(f"[ERROR] 找不到 {LIST_CSV}", file=sys.stderr)
        sys.exit(1)

    if not os.path.isdir(FASTQ_DIR):
        print(f"[WARN] fastq 目录 {FASTQ_DIR} 不存在，将无法判断是否已下载。")
        print("       如仍想继续，对所有 SRA 拉取元数据，请把 has_fastq() 检查逻辑注释掉。")

    accs = load_accessions(LIST_CSV, ACC_COL_NAME)
    print(f"[INFO] 共读取到 {len(accs)} 个 SRA accession")

    out_fields = [
        "SRA",
        "strain",
        "host",
        "collection_date",
        "geographic_location",
        "sample_type",
        "Submission",
    ]

    with open(OUT_TSV, "w", newline='', encoding="utf-8") as out_f:
        writer = csv.DictWriter(out_f, fieldnames=out_fields, delimiter="\t")
        writer.writeheader()

        for i, acc in enumerate(accs, start=1):
            # 只处理已经下载的样本
            if has_fastq(acc, FASTQ_DIR) is False:
                # 若想无论是否下载都采集元数据，把这一段 if 注释掉即可
                print(f"[SKIP] {acc}: no fastq found in {FASTQ_DIR}, skip metadata")
                continue

            print(f"[{i}/{len(accs)}] Fetching metadata for {acc} ...")
            try:
                xml_text = fetch_sra_xml(acc)
                meta = parse_metadata_from_xml(xml_text, fallback_acc=acc)
                writer.writerow(meta)
            except Exception as e:
                print(f"[WARN] Failed to fetch/parse {acc}: {e}", file=sys.stderr)
            time.sleep(SLEEP_SEC)

    print(f"[DONE] 元数据已写入: {OUT_TSV}")


if __name__ == "__main__":
    main()
