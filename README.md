# download_sra_from_list.sh
You can download the WGS data from NCBI in batches based on the accession number, and then decompress it into FASTQ format.

# -------------------------------------------------------------
# Script Name: download_sra_from_list.sh
#
# Overview:
# This script automates the batch downloading of NCBI SRA datasets.
# Given a user-supplied SraAccList.csv containing a list of SRA accessions,
# the script performs the following steps automatically:
#   1) Extract all SRA accessions from the CSV file
#   2) Download .sra files using prefetch (with resume capability)
#   3) Convert .sra to FASTQ using fasterq-dump (multi-threaded)
#   4) Optionally compress FASTQ files using pigz
#   5) Automatically skip previously downloaded samples
#
# Key Features:
#  - Fully automated and scalable for large datasets (1000+ SRAs)
#  - Safe to rerun; supports resume without re-downloading
#  - Customizable parameters (threads, compression, output folders)
#  - Ideal for WGS, metagenomics, and population genomics workflows
#
# Suitable For:
#  Large-scale SRA data retrieval in genomics research pipelines.
#
# Author: Your Name
# Version: v1.0
# -------------------------------------------------------------


# -------------------------------------------------------------
# 脚本名称（Script Name）：download_sra_from_list.sh
#
# 功能简介：
# 本脚本用于批量自动化下载 NCBI SRA 数据。通过读取用户提供的 
# SraAccList.csv（包含 SRA accession 列），脚本将自动执行以下流程：
#   1) 提取所有 SRA accession
#   2) 使用 prefetch 下载 .sra 文件（自动断点续传）
#   3) 使用 fasterq-dump 转换为 fastq（支持多线程）
#   4) 自动压缩 fastq.gz（可选，使用 pigz）
#   5) 自动跳过已下载样本，支持重复运行、安全续跑
#
# 特点：
#  - 全自动化，一条命令完成所有 WGS 数据下载
#  - 断点续跑，无需担心重复下载
#  - 可大规模下载（1000+ SRA）且稳定
#  - 用户可配置线程数、压缩方式、文件目录等参数
#
# 适用于：
#  群体基因组学、宏基因组、分型研究、大规模 SRA 下载任务
#
# 作者：Your Name
# 版本：v1.0
# -------------------------------------------------------------


