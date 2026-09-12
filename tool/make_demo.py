#!/usr/bin/env python3
"""Build the bundled, original public-domain demo. No third-party book content."""
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZipFile, ZIP_STORED, ZIP_DEFLATED

CHAPTERS = [
    ("La porte du jardin", [
        "Ce matin-là, la ville semblait avoir baissé la voix. Les volets s’ouvraient sans bruit, les premières bicyclettes glissaient entre les maisons, et une odeur de pain chaud traversait la rue. Inès marchait sans regarder l’heure.",
        "Elle avait trouvé la clé au fond d’une enveloppe. Ni adresse ni signature : seulement une phrase, écrite d’une main tranquille. « La porte est ouverte à ceux qui prennent le temps. » Elle l’avait relue trois fois avant de sortir.",
        "Au bout du chemin, derrière une grille presque cachée par les feuilles, un jardin attendait. Rien n’y paraissait extraordinaire. Un figuier, quelques bancs, une fontaine silencieuse. Pourtant, Inès eut la sensation précise d’arriver à un endroit qu’elle connaissait déjà.",
        "— Vous êtes en avance, dit une voix.\n— Je ne savais pas qu’on m’attendait.\n— Ici, nous attendons surtout que les gens cessent de se dépêcher.",
        "L’homme tenait un petit livre à la couverture verte. Il ne chercha pas à expliquer la clé ni l’enveloppe. Il lui montra simplement le banc, à l’endroit où la lumière commençait à toucher la pierre.",
        "Inès s’assit. Pour la première fois depuis longtemps, elle n’avait rien à faire avant quelque chose d’autre. Le monde pouvait continuer sans qu’elle le poursuive.",
    ]),
    ("Les pages et la lumière", [
        "Le livre ne racontait pas l’histoire d’un grand voyage. Il parlait d’une maison, d’un arbre et de deux personnes qui apprenaient à se connaître. Inès fut surprise de sentir combien cette histoire minuscule occupait d’espace en elle.",
        "— Pourquoi ce livre ? demanda-t-elle.\n— Parce qu’on n’a pas toujours besoin d’une autre vie, répondit le jardinier. Parfois, il suffit d’écouter un peu mieux celle qui est là.",
        "Une feuille se détacha du figuier. Elle tourna lentement avant de se poser entre leurs chaussures. Personne ne la ramassa. Le jardinier ouvrit le livre et commença à lire, sans chercher à donner une voix différente à chaque personnage.",
        "Il laissait les phrases respirer. Quand une question apparaissait, elle restait un instant dans l’air. Quand venait le silence, il ne se hâtait pas de le remplir. Inès suivait les mots sur la page, puis fermait les yeux pour les retrouver autrement.",
        "Sur une table étaient rangés 21 carnets et 80 petites étiquettes. Mme Diallo, qui s’occupait des semis, y notait chaque nouvelle pousse. « Les nombres sont utiles, disait-elle, mais ils ne disent pas la couleur des feuilles. »",
        "À midi, Inès avait oublié le nombre de pages qu’ils avaient lues. Elle se souvenait seulement d’une phrase sur la patience, d’une fenêtre ouverte et d’un rire arrivé au bon moment.",
    ]),
    ("Une autre façon de revenir", [
        "Lorsqu’elle quitta le jardin, rien n’avait changé dans la rue. Les voitures passaient toujours, les conversations se croisaient, et quelqu’un cherchait ses clés devant une porte bleue. Pourtant, Inès ne marchait plus de la même manière.",
        "Elle avait glissé le livre dans son sac. Le jardinier lui avait demandé de le rapporter un jour, sans préciser lequel. Elle aimait cette promesse qui ne ressemblait pas à un rendez-vous.",
        "Le soir, elle ouvrit la fenêtre. Une brise fraîche souleva le rideau. Elle posa le livre devant elle et reprit le passage où elle s’était arrêtée, d’abord à voix basse, puis en laissant les mots trouver leur place.",
        "Elle comprit alors que lire n’était pas seulement avancer vers la dernière page. C’était aussi revenir à une phrase et y découvrir quelque chose qu’on n’avait pas entendu la première fois.",
        "Le lendemain, la clé était toujours dans sa poche. Inès ne savait pas encore si elle retournerait au jardin. Pour l’instant, elle regardait la lumière entrer dans la pièce. Cela lui paraissait déjà une bonne façon de commencer.",
    ]),
]


def make_demo(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=ZIP_STORED)
        archive.writestr("META-INF/container.xml", '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
<rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>
</rootfiles></container>''', compress_type=ZIP_DEFLATED)
        items = ''.join(f'<item id="ch{i}" href="ch{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(1, 4))
        spine = ''.join(f'<itemref idref="ch{i}"/>' for i in range(1, 4))
        opf = f'''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">urn:lisiere:demo:le-jardin-des-heures:1</dc:identifier>
<dc:title>Le jardin des heures</dc:title><dc:creator>Lisière · texte de démonstration</dc:creator>
<dc:language>fr</dc:language><dc:rights>Texte original fourni pour cette application. Libre de réutilisation.</dc:rights>
<meta property="dcterms:modified">2026-09-11T00:00:00Z</meta></metadata>
<manifest>{items}<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>
<spine>{spine}</spine></package>'''
        archive.writestr("EPUB/package.opf", opf, compress_type=ZIP_DEFLATED)
        links = ''.join(f'<li><a href="ch{i}.xhtml">{escape(title)}</a></li>' for i, (title, _) in enumerate(CHAPTERS, 1))
        nav = f'''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="fr"><head><title>Sommaire</title></head><body><nav epub:type="toc"><h1>Sommaire</h1><ol>{links}</ol></nav></body></html>'''
        archive.writestr("EPUB/nav.xhtml", nav, compress_type=ZIP_DEFLATED)
        for i, (title, paragraphs) in enumerate(CHAPTERS, 1):
            body = ''.join(f'<p>{escape(p).replace(chr(10), "<br/>")}</p>' for p in paragraphs)
            if i == 1:
                body += '<p>Le jardin gardait son secret.<a epub:type="noteref" href="#n1">1</a></p>'
                body += '<aside epub:type="footnote" id="n1"><p>Cette note sert à vérifier le réglage de lecture des notes.</p></aside>'
            xhtml = f'''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="fr">
<head><title>{escape(title)}</title></head><body><h1>{escape(title)}</h1>{body}
<span epub:type="pagebreak" title="{i}">{i}</span><div hidden="hidden">Cette mention technique ne doit pas être lue.</div>
</body></html>'''
            archive.writestr(f"EPUB/ch{i}.xhtml", xhtml, compress_type=ZIP_DEFLATED)

if __name__ == "__main__":
    output = Path(__file__).resolve().parents[1] / "assets/demo.epub"
    make_demo(output)
    print(output)
