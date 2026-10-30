class_name NoteReport
extends RefCounted
## 현재 노트 전체를 HTML 한 장으로 만든다.
## 스크린샷과 음성은 base64로 파일 안에 넣어서, 이 파일 하나만 보내면 어디서든 열린다.
## 부재(anchor)별로 묶고, 충돌이 있는 부재는 위에 따로 적는다.

const CSS := """
*{box-sizing:border-box}
body{margin:0;background:#17181b;color:#ececea;font:14px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif}
.wrap{max-width:960px;margin:0 auto;padding:40px 24px 80px}
h1{font-size:24px;font-weight:600;margin:0 0 4px}
.sub{color:#9a9a97;font-size:13px;margin-bottom:28px}
.legend{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 28px}
.chip{font-size:12px;padding:3px 9px;border-radius:4px;color:#141414;font-weight:600}
.conflict{background:#2a1f1f;border:1px solid #5a3a3a;border-radius:6px;padding:12px 16px;margin-bottom:28px;font-size:13px}
.conflict b{color:#ff8a7e}
section{margin-bottom:40px}
h2{font-size:15px;font-weight:600;color:#bdbdb9;letter-spacing:.04em;text-transform:uppercase;margin:0 0 12px;padding-bottom:6px;border-bottom:1px solid #2a2b2f}
h2 .bang{color:#ff8a7e;margin-left:8px}
.note{display:grid;grid-template-columns:4px 1fr;background:#1f2024;border-radius:6px;overflow:hidden;margin-bottom:12px}
.note.resolved{opacity:.55}
.band{background:var(--c)}
.body{padding:14px 16px}
.head{display:flex;gap:10px;align-items:baseline;font-size:12px;color:#9a9a97;margin-bottom:6px}
.head .type{color:var(--c);font-weight:600;text-transform:uppercase;letter-spacing:.04em}
.head .tag{margin-left:auto;font-size:11px;padding:1px 6px;border:1px solid #3a3b40;border-radius:3px}
.text{font-size:15px;white-space:pre-wrap}
img{display:block;max-width:100%;border-radius:4px;margin:10px 0 4px}
audio{display:block;width:100%;height:32px;margin-top:8px}
.clip{position:relative;margin:10px 0 4px}
.clip img{margin:0}
.clip button{position:absolute;left:10px;bottom:10px;background:#000a;color:#fff;border:1px solid #fff5;border-radius:4px;padding:6px 12px;font-size:13px;cursor:pointer}
.clip .t{position:absolute;right:10px;bottom:12px;color:#fff;font-size:12px;background:#000a;padding:3px 6px;border-radius:3px}
.replies{margin:12px 0 0 0;padding-left:12px;border-left:2px solid #2a2b2f}
.reply{margin:8px 0;font-size:13px}
.reply .head{margin-bottom:2px}
.reply .text{font-size:13px}
.empty{color:#6e6e6c;font-style:italic}
footer{color:#6e6e6c;font-size:12px;margin-top:40px}
"""


static func build(title: String) -> String:
	var tops := NoteManager.top_level_notes()
	var groups: Dictionary = {}
	var order: Array = []
	for n in tops:
		var key := n.anchor_name if n.anchor_name != "" else "(unanchored)"
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(n)

	var counts := NoteManager.counts_by_type()
	var total := tops.size()
	var open_count := 0
	for n in tops:
		if not n.resolved:
			open_count += 1

	var h := PackedStringArray()
	h.append("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
	h.append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
	h.append("<title>%s</title><style>%s</style></head><body><div class=\"wrap\">" % [_esc(title), CSS])
	h.append("<h1>%s</h1>" % _esc(title))
	h.append("<div class=\"sub\">%d notes · %d open · exported %s</div>" % [total, open_count, _esc(Time.get_datetime_string_from_system(false, true))])

	h.append("<div class=\"legend\">")
	for i in NoteData.TYPE_NAMES.size():
		h.append("<span class=\"chip\" style=\"background:#%s\">%s %d</span>" % [NoteData.TYPE_COLORS[i].to_html(false), NoteData.TYPE_NAMES[i], counts[i]])
	h.append("</div>")

	var conflicts := NoteManager.conflict_anchors()
	if not conflicts.is_empty():
		h.append("<div class=\"conflict\"><b>Open conflicts</b> · a constraint and a proposal sit on the same part: %s</div>" % _esc(", ".join(conflicts)))

	for key in order:
		var bang := "<span class=\"bang\">! conflict</span>" if NoteManager.is_conflict(key) else ""
		h.append("<section><h2>%s%s</h2>" % [_esc(key), bang])
		for n in groups[key]:
			h.append(_note_html(n))
		h.append("</section>")

	h.append("<footer>Made with habitat_notes (Godot). Clips, screenshots and voice are embedded in this file.</footer>")
	h.append(JS)
	h.append("</div></body></html>")
	return "".join(h)


static func _note_html(n: NoteData) -> String:
	var c := n.color().to_html(false)
	var s := PackedStringArray()
	s.append("<div class=\"note%s\" style=\"--c:#%s\"><div class=\"band\"></div><div class=\"body\">" % [" resolved" if n.resolved else "", c])
	s.append(_head(n, true))
	s.append(_media_html(n))
	if n.text != "":
		s.append("<div class=\"text\">%s</div>" % _esc(n.text))
	var replies := NoteManager.replies_of(n.id)
	if not replies.is_empty():
		s.append("<div class=\"replies\">")
		for r in replies:
			s.append("<div class=\"reply\" style=\"--c:#%s\">" % r.color().to_html(false))
			s.append(_head(r, false))
			s.append(_media_html(r))
			if r.text != "":
				s.append("<div class=\"text\">%s</div>" % _esc(r.text))
			s.append("</div>")
		s.append("</div>")
	s.append("</div></div>")
	return "".join(s)


static func _head(n: NoteData, with_tag: bool) -> String:
	var tag := ""
	if with_tag:
		tag = "<span class=\"tag\">%s</span>" % ("resolved" if n.resolved else "open")
	return "<div class=\"head\"><span class=\"type\">%s</span><span>%s</span><span>%s</span><span>%s</span>%s</div>" % [
		_esc(n.type_name()), _esc(n.role_name()), _esc(n.author), _esc(n.created_at), tag]


## 클립이 있으면 프레임 슬라이드쇼 + 음성, 없으면 썸네일 + 음성
static func _media_html(n: NoteData) -> String:
	var meta := NoteManager.load_clip(n.clip_file) if n.has_clip() else {}
	if not meta.is_empty() and str(meta.get("mode", "")) == "ffmpeg":
		var mp4 := str(meta.get("mp4_path", ""))
		if FileAccess.file_exists(mp4):
			var bytes := FileAccess.get_file_as_bytes(mp4)
			if not bytes.is_empty():
				return "<video controls preload=\"metadata\" style=\"display:block;max-width:100%;border-radius:4px;margin:10px 0 4px\" src=\"data:video/mp4;base64,%s\"></video>" % Marshalls.raw_to_base64(bytes)
	if not meta.is_empty() and str(meta.get("mode", "frames")) != "ffmpeg":
		var frames := PackedStringArray()
		for i in range(1, int(meta["frames"]) + 1):
			var bytes := FileAccess.get_file_as_bytes(NoteManager.clip_frame_path(meta, i))
			if not bytes.is_empty():
				frames.append("\"data:image/jpeg;base64,%s\"" % Marshalls.raw_to_base64(bytes))
		if not frames.is_empty():
			var aud := _audio_uri(str(meta.get("audio_file", "")))
			var out := "<div class=\"clip\" data-fps=\"%s\" data-dur=\"%.2f\"><img src=%s alt=\"\"><button>▶ Play clip</button><span class=\"t\">%.0fs</span>" % [
				str(meta["fps"]), float(meta.get("duration", 0.0)), frames[0], float(meta.get("duration", 0.0))]
			if aud != "":
				out += "<audio preload=\"none\" src=\"%s\"></audio>" % aud
			out += "<script type=\"application/json\">[%s]</script></div>" % ",".join(frames)
			return out
	var s := ""
	var img := _img_uri(n.screenshot_file)
	if img != "":
		s += "<img src=\"%s\" alt=\"\">" % img
	var aud := _audio_uri(n.audio_file)
	if aud != "":
		s += "<audio controls preload=\"none\" src=\"%s\"></audio>" % aud
	if s == "" and n.text == "":
		s = "<div class=\"text\"><span class=\"empty\">no media</span></div>"
	return s


const JS := """
<script>
document.querySelectorAll('.clip').forEach(function(c){
  var frames=JSON.parse(c.querySelector('script').textContent);
  var img=c.querySelector('img'), btn=c.querySelector('button'), t=c.querySelector('.t');
  var audio=c.querySelector('audio'), fps=parseFloat(c.dataset.fps), dur=parseFloat(c.dataset.dur);
  var playing=false, start=0, raf=0;
  function stop(){playing=false;cancelAnimationFrame(raf);if(audio){audio.pause();audio.currentTime=0;}img.src=frames[0];btn.textContent='▶ Play clip';t.textContent=dur.toFixed(0)+'s';}
  function tick(){if(!playing)return;var el=audio&&!audio.paused?audio.currentTime:(performance.now()-start)/1000;
    var i=Math.min(frames.length-1,Math.floor(el*fps));img.src=frames[i];t.textContent=el.toFixed(1)+' / '+dur.toFixed(0)+'s';
    if(el>=dur&&(!audio||audio.ended||audio.paused)){stop();return;}raf=requestAnimationFrame(tick);}
  btn.onclick=function(){if(playing){stop();return;}playing=true;start=performance.now();btn.textContent='■ Stop';if(audio){audio.play();}tick();};
});
</script>"""


static func _img_uri(file: String) -> String:
	if file == "":
		return ""
	var path := NoteManager.MEDIA_DIR + file
	if not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	return "data:image/png;base64," + Marshalls.raw_to_base64(bytes)


static func _audio_uri(file: String) -> String:
	if file == "":
		return ""
	var path := NoteManager.MEDIA_DIR + file
	if not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	return "data:audio/wav;base64," + Marshalls.raw_to_base64(bytes)


static func _esc(s: String) -> String:
	return s.xml_escape()
