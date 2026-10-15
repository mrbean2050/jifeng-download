#!/bin/bash
set -euo pipefail
cd "$1"
./configure --arch=arm64 --target-os=darwin --cc=clang --extra-cflags=-mmacosx-version-min=13.0 --extra-ldflags=-mmacosx-version-min=13.0 --disable-everything --disable-autodetect --disable-doc --disable-debug --disable-asm --disable-ffplay --disable-ffprobe --disable-network --enable-protocol=file --enable-demuxer=mov,matroska,avi,mpegts,aac,mp3,ogg,h264,hevc,av1 --enable-muxer=matroska,mp4,mov,webm,adts,mp3,ogg --enable-parser=aac,h264,hevc,av1,opus --enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb
make -j8
