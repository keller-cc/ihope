import fitz
from pathlib import Path

dest = Path(r"D:\IHope\web\public\games\manila\board\original")
for pdf_name in ["Manila-rules-WOBG.pdf", "Manila-rules-tojeto.pdf"]:
    pdf = dest / pdf_name
    if not pdf.exists():
        print("missing", pdf)
        continue
    doc = fitz.open(pdf)
    print(pdf_name, "pages", doc.page_count)
    for i in range(min(3, doc.page_count)):
        page = doc[i]
        pix = page.get_pixmap(matrix=fitz.Matrix(2.2, 2.2), alpha=False)
        out = dest / f"{pdf.stem}-page{i+1}.png"
        pix.save(out)
        print("wrote", out.name, out.stat().st_size)
    n = 0
    for i in range(doc.page_count):
        for img in doc.get_page_images(i):
            xref = img[0]
            try:
                data = doc.extract_image(xref)
            except Exception:
                continue
            blob = data["image"]
            if len(blob) < 30000:
                continue
            n += 1
            ext = data.get("ext", "png")
            out = dest / f"{pdf.stem}-embed{n}.{ext}"
            out.write_bytes(blob)
            print(
                "embed",
                out.name,
                len(blob),
                "w",
                data.get("width"),
                "h",
                data.get("height"),
            )
    doc.close()
print("done")
