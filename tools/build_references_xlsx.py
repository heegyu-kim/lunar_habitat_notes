# -*- coding: utf-8 -*-
"""Writes docs/habitat_references.xlsx: reference cases, dimension standards, module programme.
Run:  python tools/build_references_xlsx.py"""
import os
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill, Border, Side
from openpyxl.utils import get_column_letter

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "habitat_references.xlsx")

HEAD_FILL = PatternFill("solid", fgColor="1F3A5F")
HEAD_FONT = Font(name="Arial", bold=True, color="FFFFFF", size=10)
BODY_FONT = Font(name="Arial", size=10)
NOTE_FONT = Font(name="Arial", size=9, italic=True, color="555555")
THIN = Side(style="thin", color="BBBBBB")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(wrap_text=True, vertical="top")

REFERENCES = [
    # 번호, 사례, 기관/저자, 구분, 연도, 검색어, 무엇을 볼지, 우리 설계 적용, URL
    (1, "Internal Layout of a Lunar Surface Habitat (Artemis Surface Habitat 참조 설계)", "NASA JSC / MSFC, Burke·Howard·Kessler", "공식 논문", 2022,
     "NASA Surface Habitat Artemis hybrid inflatable internal layout",
     "우리 코어 타워의 원본. 금속 Ø4.4×2.6 + 인플레이터블 Ø6.5×5.2, 코어 Ø3.3, 3층 구성, 수트포트 에어락, Collins 팔레트 10개, 기능별 최소 면적 표, 설계 결함 목록",
     "A 모듈 그대로. 침실 벽 공유 결함을 일부러 남김. 면적 표가 모든 실 크기의 기준",
     "https://ntrs.nasa.gov/api/citations/20220013669/downloads/Internal%20Layout%20of%20a%20Lunar%20Surface%20Habitat.pdf"),
    (2, "Foundation Surface Habitat 개요", "NASA", "공식 발표자료", 2023,
     "Foundation Surface Habitat NASA 2023",
     "4인·최대 1,100일·건조질량 약 25 t 급 후속 개념. 의료·운동·조리·침실·수납 구성과 외형",
     "4인 확장의 근거. C 거주 모듈 규모 설정",
     "https://ntrs.nasa.gov/api/citations/20230012221/downloads/Cohenartemispresentation.pdf"),
    (3, "40 kWe Deployable Fission Surface Power", "NASA", "공식 논문", 2022,
     "NASA Fission Surface Power deployable 40 kWe",
     "원자로 이격 약 1 km, 50 m에서 제어전자 차폐 불필요, 고전압 케이블 + 변환기, 레골리스 차폐 대안",
     "원자로를 600~1,000 m 북쪽 성토 뒤에, 케이블 트레이로 B4에 인입",
     "https://ntrs.nasa.gov/api/citations/20220004670/downloads/40%20kW%20Deployable%20FSP%20Paper_FINAL.pdf"),
    (4, "Fission Surface Power 1단계 완료 (6 t 이하·40 kW·10년)", "NASA / Nuclear Engineering International", "보도", 2024,
     "NASA Fission Surface Power phase 1 complete",
     "원자로 사양(질량·출력·수명)과 2030년대 초 발사 목표",
     "원자로 외형 크기(Ø2.4×3 m + 방열핀) 근거",
     "https://www.neimagazine.com/news/nasa-completes-initial-phase-of-lunar-nuclear-reactor-project-11494315/"),
    (5, "A Baseline Design for the Space Station Habitat", "SAE 881119", "논문", 1988,
     "Space Station Habitat baseline design acoustics quiet zone buffer",
     "활동·음향 기준 3구역: 조용한 침실 구역 / 수납·위생 완충 구역 / 작업 구역",
     "구역 프리셋의 조용·완충·시끄러움 3분류와 C 모듈 배치 원칙",
     "https://saemobilus.sae.org/papers/a-baseline-design-space-station-habitat-881119"),
    (6, "Gateway I-HAB Interior (IAC 2019)", "LIQUIFER Systems Group", "논문", 2019,
     "LIQUIFER I-HAB interior IAC 2019",
     "50 m³ 미만 모듈에서도 작업 공간과 거주 공간 분리를 설계 요구사항으로 둔 사례. 인테리어 디테일",
     "작업·거주 분리의 근거. 인플레이터블 내벽 디테일 참고",
     "https://liquifer.com/wp-content/uploads/2020/03/2019_Interior_IAC-Paper-Liquifer-2019_v3.pdf"),
    (7, "Dust Mitigation in Lunar Habitats (WERC 2025 Task 4)", "NMSU", "설계 과제 자료", 2025,
     "WERC 2025 dust mitigation lunar habitat airlock",
     "에어락이 먼지 1차 방어선, 수트와 CTB 가방을 에어락에서 털기, 0.5~50 μm 먼지의 아폴로 피해",
     "B1 먼지 전실(흡입 그릴·에어샤워)과 먼지 동선",
     "https://werc.nmsu.edu/team-info/WERC-2025-Task-4-Dust-Mitigation-in-Lunar-Habitats1.pdf"),
    (8, "Lunar homes: Tiny rooms, but they repel dust and solar storms (JSC 목업)", "Christian Science Monitor", "기사", 2006,
     "JSC lunar habitat mockup 2006 storm shelter water tanks",
     "1층 생명유지·공용·4인 에어락, 생활은 위층. 태양 폭풍 최대 4일, 물탱크·대형 장비를 외벽 둘레에 배치해 차폐",
     "C 1층 물탱크 대피소 벽",
     "https://csmonitor.com/2006/0713/p01s01-usgn.html"),
    (9, "SOM + ESA + MIT Moon Village", "SOM", "건축 개념", 2021,
     "SOM Moon Village ESA Venice Biennale",
     "3~4층 인플레이터블 모듈 군집, 레골리스 외피(온도·충돌·먼지·방사선), 섀클턴 크레이터 림 입지, 3단계 성장",
     "C 모듈 레골리스 성토, 군집 배치의 외형",
     "https://www.som.com/news/som-releases-concept-for-moon-village-the-first-permanent-human-settlement-on-the-lunar-surface/"),
    (10, "SOM releases conceptual design for lunar development", "Architectural Record", "기사", 2021,
     "SOM lunar development Architectural Record",
     "Moon Village 렌더링과 단면 이미지",
     "외피·창 배치 이미지 참고",
     "https://architecturalrecord.com/articles/14009-som-releases-conceptual-design-for-lunar-development"),
    (11, "First Lunar Outpost Habitat Study", "NASA / SICSA", "연구 보고서", 1993,
     "SICSA First Lunar Outpost habitat study",
     "침실·대피소·갤리·워드룸 기능, 방사선 차폐·ECLSS·대피소 운용·EVA 요구 분석",
     "실 기능 목록과 대피소 운용 개념",
     "https://ntrs.nasa.gov/api/citations/19930013865/downloads/19930013865.pdf"),
    (12, "NASA Habitat Demonstration Unit (HDU) / Deep Space Habitat 목업", "NASA JSC", "실물 목업", 2010,
     "NASA Habitat Demonstration Unit interior; Deep Space Habitat mockup Johnson",
     "실제 목업의 작업대·수납·조명·손잡이 밀도. '우주 장비답게' 보이는 디테일의 기준",
     "장비·가구 디테일 수준, 트림 시트 요소(패널 라인·리벳·라벨)",
     "(이미지 검색)"),
    (13, "ISS 모듈 내부 (Node 2, Destiny, 승무원 침실)", "NASA / ESA", "실물", 2000,
     "ISS Node 2 interior; Destiny lab rack; ISS crew quarters",
     "랙 모듈화, 손잡이, 라벨, 케이블, 팬 그릴, 침실 흡음 패널",
     "팔레트·랙 표현, 침실 방음 커튼·패널",
     "(이미지 검색)"),
    (14, "Bigelow BEAM / B330", "Bigelow Aerospace", "실물·개념", 2016,
     "Bigelow BEAM interior; B330 habitat",
     "인플레이터블 내벽 질감(직물, 스트랩, 봉제선)",
     "C 모듈과 A 상부 내벽 재질",
     "(이미지 검색)"),
    (15, "Sierra Space LIFE Habitat", "Sierra Space", "실물 시험체·개념", 2023,
     "Sierra Space LIFE habitat interior",
     "3층 인플레이터블의 수직 구성, 사다리·개구부, 층별 배치",
     "C 2층 구성, 사다리 개구 크기",
     "(이미지 검색)"),
    (16, "Mars Dune Alpha (NASA CHAPEA)", "ICON / NASA", "실물", 2023,
     "Mars Dune Alpha interior CHAPEA",
     "4인 1년 거주 평면, 침실·공용 비율, 색·재질로 구역을 나눈 방식, 온실",
     "구역별 재질 팔레트, 온실 랙",
     "(이미지 검색)"),
    (17, "ESA 3D 프린팅 달 기지 개념", "Foster + Partners / ESA", "건축 개념", 2013,
     "Foster Partners lunar base ESA 3D printed regolith",
     "인플레이터블 돔 위 레골리스 외피 형태, 성토 단면",
     "C 모듈 성토 형태",
     "(이미지 검색)"),
    (18, "ESA 달 거주지 개념 (Hassell)", "Hassell / ESA", "건축 개념", 2018,
     "Hassell ESA lunar habitat",
     "거주 구역의 따뜻한 재질·조명, 모듈 군집",
     "거주 구역 2,700~3,200 K 조명, 베이지 직물",
     "(이미지 검색)"),
    (19, "MARSHA", "AI SpaceFactory", "건축 개념", 2019,
     "AI SpaceFactory MARSHA interior",
     "수직 다층 거주지의 층별 분위기 변화, 창 배치",
     "층마다 색온도·재질을 바꾸는 방식",
     "(이미지 검색)"),
    (20, "Lunar Terrain Vehicle / Lunar Cruiser", "NASA / Toyota·JAXA", "차량", 2024,
     "NASA Lunar Terrain Vehicle; Toyota Lunar Cruiser",
     "외부 차량 크기·바퀴·도킹 포트 감각",
     "LTV·가압 로버 외형, 허브 남쪽 도킹 포트",
     "(이미지 검색)"),
    (21, "Human Integration Design Handbook (NASA/SP-2010-3407) · NASA-STD-3001 Vol.2", "NASA", "표준", 2010,
     "Human Integration Design Handbook habitability volume",
     "순거주체적(NHV) 산정 방법, 기능별 최소 치수, 통로·해치·조명·음향 기준",
     "치수 표의 상위 근거 (논문 1이 이를 인용)",
     "https://ntrs.nasa.gov/citations/20100021017"),
]

DIMENSIONS = [
    # 항목, 값, 단위, 근거, 비고
    ("통로 폭 (최소)", 1.0, "m", "NASA Foundation Surface Habitat NHV 권고 (논문 1, Table 1)", "팔레트 앞 정비 통로도 동일"),
    ("표준 높이 (기능 체적 산정)", 2.4, "m", "논문 1 §IV", "99퍼센타일 체격 기준"),
    ("에어락 / 수트 착탈 높이", 2.6, "m", "논문 1 §IV", "헤드룸 필요"),
    ("취침 체적 높이", 1.0, "m", "논문 1 §IV", "침상 위 앉을 공간; 개인 침실 강력 권장"),
    ("취침 면적 (1인)", 1.82, "m²", "논문 1 Table 1", "중력 환경 수평 취침"),
    ("스트레칭 면적 (1인)", 1.40, "m²", "논문 1 Table 1", "옷 갈아입기는 취침과 겹칠 수 없음"),
    ("개인 침실 바닥 면적 (가안)", 4.5, "m²", "취침 + 스트레칭 + 책상, 논문 1 §VII(확장 요구)", "NASA 레이아웃 실측 1.85/인 취침 + 1.34/인 스트레칭"),
    ("위생 스테이션", 1.06, "m²", "논문 1 Table 1", "습식·건식 겸용"),
    ("UWMS (화장실)", 0.91, "m²", "논문 1 Table 1", "정비까지 구획 내"),
    ("워드룸 테이블 (전원 식사)", 1.62, "m²", "논문 1 Table 1", "영화·게임·회의 겸용, 창 인접"),
    ("조리: 식품 분류 + 조리", 1.12, "m²", "논문 1 Table 1 (0.56 + 0.56)", "접이식 작업면"),
    ("의료", 1.87, "m²", "논문 1 Table 1", "들것 수납, 커튼"),
    ("운동 (저항 운동기구)", 1.50, "m²", "논문 1 Table 1", "E4D 유사 기구 1대"),
    ("정비 작업대", 1.37, "m²", "논문 1 Table 1", "전자 수리·수트 부품·물류 포장 겸용"),
    ("지휘·감시 컴퓨터", 1.82, "m²", "논문 1 Table 1", ""),
    ("에어락 바닥 면적", 5.0, "m²", "논문 1 Table 4", "레이아웃 실측 5.18"),
    ("순거주체적 (2인 SH)", 127, "m³", "논문 1 §V", "1인당 약 64 m³"),
    ("Collins 범용 팔레트 길이", 1.83, "m", "논문 1 §V (72 in)", "표준 해치 통과 규격"),
    ("Collins 범용 팔레트 단면", 0.77, "m", "논문 1 §V (30.19 in)", ""),
    ("코어 타워 금속부 직경", 4.4, "m", "논문 1 §II", "높이 2.6"),
    ("코어 타워 인플레이터블 외경", 6.5, "m", "논문 1 §II", "높이 5.2, 코어 Ø3.3"),
    ("NASA 표준 해치 (ISS CBM)", 1.27, "m", "ISS Common Berthing Mechanism 해치 50 in", "사각 1.27 × 1.27; 세로 타원형 출입문은 0.9 × 1.9 가안"),
    ("층간 높이 (가안)", 2.6, "m", "논문 1 구조 (2.6 / 5.2 데크)", "파이프라인은 2.0 m 이상이면 별도 층"),
    ("B 모듈 직경 × 길이 (가안)", "4.4 × 16", "m", "금속 압력용기 직경은 논문 1 하부와 동일", "바닥 폭 3.3~3.8"),
    ("C 모듈 외경 × 높이 (가안)", "7.5 × 5.8", "m", "Foundation SH 4인 확장 규모 참고", "2층 + 돔"),
    ("원자로 이격 거리", "600~1,000", "m", "NASA 40 kWe FSP 전개형 연구 (약 1 km 대표값)", "50 m에서 제어전자 차폐 불필요"),
    ("원자로 사양", "40 kWe, ≤6 t, 10년", "", "NASA FSP 1단계 요구", ""),
    ("태양 폭풍 대피 기간", 4, "일", "JSC 목업 기사 (2006)", "물탱크·장비를 외벽 둘레에"),
    ("침실 허용 소음 (가안)", 35, "dB", "도구 프리셋; ISS 침실 흡음 설계 취지", "이 도구의 어림값"),
    ("레골리스 성토 높이 (가안)", 3.5, "m", "SOM Moon Village 외피 개념", "거주 모듈 2/3 높이"),
]

PROGRAMME = [
    # 모듈, 실, 유형(프리셋), 면적 m², 주요 장비, 성격
    ("A 코어 L1", "수트포트 에어락", "airlock", 5.0, "외부 해치, 내부 해치, 수트포트 2", "시끄러움·더러움"),
    ("A 코어 L1", "작업대·지질·EVA 컴퓨터·OGA", "workshop", 6.0, "작업대, 지질 실험대, OGA 팔레트 2, 화물 수트포트", "시끄러움"),
    ("A 코어 L2", "위생·UWMS", "hygiene", 2.0, "위생 스테이션, UWMS 구획", "완충"),
    ("A 코어 L2", "운동", "exercise", 2.1, "E4D 유사 기구", "시끄러움"),
    ("A 코어 L2", "생물 실험대", "lab", 2.5, "", "완충"),
    ("A 코어 L2", "물 처리", "eclss", 4.0, "WPA 3, UP/BP 2, 물탱크", "시끄러움"),
    ("A 코어 L3", "침실 1, 2", "crew_quarters", 3.7, "침상, 책상 (벽 공유 결함)", "조용"),
    ("A 코어 L3", "의무실", "medical", 3.4, "들것, 커튼", "조용"),
    ("A 코어 L3", "조리·워드룸", "galley", 3.4, "테이블, 조리대, 창", "완충"),
    ("A 코어 L3", "ARS·실험", "eclss", 5.0, "ARS 팔레트 3, 물리·인간연구 실험대", "시끄러움"),
    ("B1", "먼지 전실·에어락", "airlock", 8.0, "수트 거치 4, 흡입 그릴, 에어샤워, 압력 패널", "시끄러움·더러움"),
    ("B2", "수트 정비", "workshop", 6.0, "수트 작업대, 부품 선반, 충전랙, 헬멧 거치", "시끄러움"),
    ("B3", "ECLSS 베이", "eclss", 14.0, "팔레트 8 한 줄, 덕트, O₂/N₂ 탱크", "시끄러움"),
    ("B4", "전력·열", "power", 8.0, "전력 캐비닛, 배터리, 펌프, 매니폴드, 상태 벽", "시끄러움"),
    ("B5", "공방", "workshop", 8.0, "작업대, 3D 프린터, 서랍, 바이스", "시끄러움·더러움"),
    ("B6", "물류", "logistics", 10.0, "CTB 랙, 냉동고 2, 압축기, 재고 단말", "완충"),
    ("D", "허브", "corridor", 12.0, "해치 4, 소화기, 마스크, 압력 패널", "완충"),
    ("C 1층", "침실 A~D", "crew_quarters", 4.5, "침상 2.0×0.85 (h0.5), 책상, 로커, 개인등, 커튼", "조용"),
    ("C 1층", "위생 A, B", "hygiene", 1.1, "세면·샤워", "완충"),
    ("C 1층", "UWMS", "uwms", 1.0, "독립 구획", "완충"),
    ("C 1층", "수납", "logistics", 1.5, "소모품 로커", "완충"),
    ("C 1층", "대피소 (중앙)", "shelter", 9.6, "물탱크 벽 1,000 L, SHELTER 표시", "조용"),
    ("C 2층", "워드룸·갤리", "galley", 4.4, "테이블 Ø1.4, 의자 4, 조리대, 냉장, 창(지구)", "완충"),
    ("C 2층", "의무실", "medical", 3.4, "들것, 의료 키트 벽, 원격의료 모니터, 커튼", "조용"),
    ("C 2층", "운동", "exercise", 2.1, "저항 기구, 자전거, 창(서)", "시끄러움"),
    ("C 2층", "온실", "greenhouse", 4.0, "생장 랙 2, LED 5,500 K", "조용"),
]


def sheet(ws, headers, rows, widths, note):
    ws.append(headers)
    for c in range(1, len(headers) + 1):
        cell = ws.cell(row=1, column=c)
        cell.fill = HEAD_FILL; cell.font = HEAD_FONT; cell.alignment = Alignment(wrap_text=True, vertical="center"); cell.border = BORDER
    for r in rows:
        ws.append(list(r))
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row, max_col=len(headers)):
        for cell in row:
            cell.font = BODY_FONT; cell.alignment = WRAP; cell.border = BORDER
            if isinstance(cell.value, str) and cell.value.startswith("http"):
                cell.hyperlink = cell.value
                cell.font = Font(name="Arial", size=10, color="0563C1", underline="single")
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = f"A1:{get_column_letter(len(headers))}{ws.max_row}"
    ws.cell(row=ws.max_row + 2, column=1, value=note).font = NOTE_FONT


def main():
    wb = Workbook()
    ws = wb.active; ws.title = "참고 사례"
    sheet(ws, ["번호", "사례", "기관 / 저자", "구분", "연도", "이미지·문헌 검색어", "무엇을 볼지", "우리 설계에 적용", "URL"],
          REFERENCES, [6, 40, 24, 12, 7, 34, 50, 40, 60],
          "작성 2026-11-07. '(이미지 검색)'은 공식 URL을 확인하지 않은 항목: 검색어로 이미지를 찾아 보고, 인용이 필요하면 원 출처를 따로 확인할 것.")
    ws2 = wb.create_sheet("치수 기준")
    sheet(ws2, ["항목", "값", "단위", "근거", "비고"], DIMENSIONS, [36, 16, 7, 54, 44],
          "'가안'은 우리 결정값. 나머지는 NASA 논문 1(Burke·Howard·Kessler 2022)과 그 상위 표준(HIDH, NASA-STD-3001)에서 가져옴. 논문 번호는 '참고 사례' 시트의 번호.")
    ws3 = wb.create_sheet("실 프로그램")
    sheet(ws3, ["모듈", "실", "구역 프리셋", "면적 (m², 가안)", "주요 장비 (모델링 대상)", "성격"], PROGRAMME, [12, 28, 16, 14, 56, 16],
          "면적은 docs/MODELING_GUIDE.md §2~3 기준의 가안. 구역 프리셋 키는 addons/sticky_notes/space/space_presets.gd 와 같다.")
    wb.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
