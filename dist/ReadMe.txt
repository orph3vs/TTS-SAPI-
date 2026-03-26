Windows 기본 음성 엔진(SAPI)을 이용한 텍스트 음성 변환 프로그램입니다.

실행 방법
1. `audio_creator.cmd`를 실행합니다.
2. 같은 폴더 안의 `script` 폴더에 변환할 `.txt` 파일을 넣습니다.
3. 실행이 끝나면 `audio_data` 폴더에 같은 이름의 `.wav` 파일이 생성됩니다.

폴더 구조
- `audio_creator.cmd`: 실행용 배치 파일
- `audio_creator.ps1`: 실제 변환 로직
- `script`: 입력 텍스트 파일 폴더
- `audio_data`: 생성된 음성 파일 폴더

동작 방식
- `script` 폴더의 모든 `.txt` 파일을 순서대로 읽습니다.
- Windows에 설치된 한국어 음성이 있으면 우선 사용합니다.
- 한국어 음성이 없으면 기본 음성으로 대체합니다.
- 결과 파일은 `audio_data` 폴더에 `8kHz mono .wav` 형식으로 저장합니다.

주의 사항
- 이 버전은 Python이나 ffmpeg가 없어도 실행됩니다.
- 음성 품질과 발음은 Windows에 설치된 음성 엔진에 따라 달라집니다.
- 텍스트 파일은 UTF-8 또는 기본 Windows 인코딩(예: CP949)으로 저장해 두면 됩니다.
