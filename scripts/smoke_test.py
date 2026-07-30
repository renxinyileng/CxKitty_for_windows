#!/usr/bin/env python3
"""离线冒烟测试: 校验运行环境和依赖是否可用。

不访问超星任何接口, 只验证:
  - 全部模块可导入 (依赖版本兼容)
  - 验证码识别链路 (opencv + numpy + onnxruntime + ddddocr)
  - 人脸上传的图像处理与 multipart 组包 (opencv + requests)
  - 题目 HTML 解析 (bs4 + lxml)
  - 试题导出 (dataclasses-json)
  - TUI 渲染 (rich)
  - 二维码登录用的终端二维码 (qrcode)

用法:
    <解释器> scripts/smoke_test.py
"""
import io
import os
import sys
import tempfile
import traceback
from pathlib import Path

# Windows 上 stdout 不是控制台 (被重定向/管道) 时, python 会退回到 locale 编码
# (如 cp1252), 打印中文直接 UnicodeEncodeError。这里强制按 UTF-8 输出。
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

APP_DIR = Path(__file__).resolve().parent.parent / "app"
# 程序会以相对路径读取 config.yml / pyproject.toml, 故必须切到 app 目录
os.chdir(APP_DIR)
if str(APP_DIR) not in sys.path:
    sys.path.insert(0, str(APP_DIR))

failures = []


def check(name, fn):
    try:
        result = fn()
    except Exception:
        failures.append(name)
        print(f"FAIL  {name}")
        traceback.print_exc()
    else:
        print(f"ok    {name} -> {str(result)[:100]}")


def test_versions():
    import importlib.metadata as md

    names = ["numpy", "onnxruntime", "opencv-python-headless", "opencv-python",
             "rich", "beautifulsoup4", "lxml", "requests", "pillow", "ddddocr"]
    got = []
    for n in names:
        try:
            got.append(f"{n}={md.version(n)}")
        except md.PackageNotFoundError:
            pass
    return f"python={sys.version.split()[0]} " + " ".join(got)


def test_imports():
    import importlib

    for mod in ["config", "logger", "cxapi", "utils", "resolver", "dialog",
                "cxapi.exam", "cxapi.task_point.work", "resolver.searcher.restapi"]:
        importlib.import_module(mod)
    return "全部模块导入成功"


def test_captcha():
    import cv2
    import numpy as np

    from cxapi.session import identify_captcha

    img = np.full((60, 160), 255, np.uint8)
    cv2.putText(img, "7g4k", (8, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.4, 0, 3)
    _, buf = cv2.imencode(".png", img)
    code = identify_captcha(buf.tobytes())
    assert isinstance(code, str) and code, f"识别结果异常: {code!r}"
    return f"识别为 {code!r}"


def test_face_upload_pipeline():
    import cv2
    import numpy as np
    from requests.models import PreparedRequest

    path = os.path.join(tempfile.mkdtemp(), "face.jpg")
    cv2.imwrite(path, np.random.default_rng(1).integers(0, 255, (40, 40, 3), dtype=np.uint8))
    face = cv2.imread(path)
    height, width, _ = face.shape
    rng = np.random.default_rng()
    for _ in range(rng.integers(0, 5)):
        face[rng.integers(0, height - 1), rng.integers(0, width - 1), rng.integers(0, 2)] += rng.integers(-2, 2)
    _, data = cv2.imencode(".jpg", face)

    req = PreparedRequest()
    req.prepare_method("POST")
    req.prepare_url("https://example.com/upload", None)
    req.prepare_headers({})
    req.prepare_body(data=None, files={"file": ("1.jpg", data.tobytes(), "image/jpeg")})
    assert isinstance(req.body, bytes) and len(req.body) > 0
    return f"multipart {len(req.body)} 字节"


def test_html_parse():
    from bs4 import BeautifulSoup

    from cxapi.task_point.work import parse_question

    html = (
        '<div class="Py-mian1"><input id="answertype9" value="0">'
        '<div class="Py-m1-title"><span>1.</span><span>(5分)</span>题干</div>'
        '<input class="answerInput" value="A">'
        '<li class="more-choose-item"><em class="choose-opt" id-param="A"></em>'
        '<div class="choose-desc"><cc>选项甲</cc></div></li></div>'
    )
    q = parse_question(BeautifulSoup(html, "lxml").select_one("div.Py-mian1"))
    assert q.id == 9 and q.value == "题干" and q.options == {"A": "选项甲"} and q.answer == "A", q
    return q


def test_export():
    from cxapi.schema import (QuestionModel, QuestionsExportSchema,
                              QuestionsExportType, QuestionType)

    schema = QuestionsExportSchema(
        id="1", title="t", type=QuestionsExportType.Exam,
        questions=[QuestionModel(id=1, value="q", type=QuestionType.判断题, options=None, answer=True)],
    )
    out = schema.to_json(ensure_ascii=False, separators=(",", ":"))
    assert '"type":0' in out and '"answer":true' in out, out
    return out


def test_tui():
    from rich.console import Console
    from rich.layout import Layout
    from rich.live import Live
    from rich.panel import Panel

    from cxapi.chapters import ChapterContainer
    from cxapi.schema import ChapterModel
    from resolver.question import MyTable

    console = Console(file=io.StringIO(), width=120, height=25)
    layout, left, right = Layout(), Layout(name="L"), Layout(name="R", size=60)
    layout.split_row(left, right)

    table = MyTable("题号 / id", "类型", "题目", "答案", expand=True, border_style="yellow")
    table.push_row("1", "单选题", "题干", "[green]A")
    left.update(table)

    chapters = [
        ChapterModel(chapter_id=i, jobs=1, index=i, name=f"章节{i}", label=f"1.{i}",
                     layer=1, status="", point_total=2, point_finished=i % 3)
        for i in range(30)
    ]
    container = ChapterContainer.__new__(ChapterContainer)
    container.chapters, container.tui_index, container.name = chapters, 12, "课程"
    right.update(Panel(container, title="章节列表", border_style="blue"))

    with Live(layout, console=console):
        pass
    out = console.file.getvalue()
    assert "❱" in out, "章节列表指针未渲染"
    return f"{len(out.splitlines())} 行"


def test_qrcode():
    from qrcode import QRCode

    qr = QRCode()
    qr.add_data("https://passport2.chaoxing.com/toauthlogin")
    buf = io.StringIO()
    qr.print_ascii(out=buf)
    assert len(buf.getvalue()) > 100
    return f"{len(buf.getvalue())} 字节"


if __name__ == "__main__":
    print(f"工作目录: {APP_DIR}\n")
    check("依赖版本", test_versions)
    check("模块导入", test_imports)
    check("验证码识别", test_captcha)
    check("人脸上传链路", test_face_upload_pipeline)
    check("题目 HTML 解析", test_html_parse)
    check("试题导出", test_export)
    check("TUI 渲染", test_tui)
    check("终端二维码", test_qrcode)

    print()
    if failures:
        print(f"共 {len(failures)} 项失败: {', '.join(failures)}")
        sys.exit(1)
    print("全部通过")
