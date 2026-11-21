Clips for voiceid-tests.swift (the owner's voice). They are not in this repository: they are speech of macOS system
voices, which Apple's licence allows for personal use only. Without them, Tests/run.sh skips the voice id checks that
need audio (the speaker model, learning and enrolment) and runs the rest.

To make them on your own Mac (offline, nothing is played): 16 kHz mono 16-bit WAV, v<voice>_p<phrase>_r170.wav,
with the Korean system voices v3 Grandpa, v5 Rocko, v6 Sandy and v8 Yuna, for example
  say -v "Yuna (한국어(한국))" -r 170 -o v8_p0_r170.wav --file-format=WAVE --data-format=LEI16@16000 "아리스"
Phrases: p0 아리스, p3 응 보내 줘, p4 그래 그렇게 해, p5 오늘 회의는 세 시에 시작해요, p6 점심 뭐 먹을지 아직 못
정했어, p7 그 파일은 어제 보내 드렸어요, p8 지하철이 또 늦게 왔어, p9 이번 주말에 비 온다고 하던데, p11 내일 아침
일곱 시에 깨워 줘, p12 엄마한테 늦는다고 문자 보내 줘, p13 다운로드 폴더 정리해 줘.
