#!/usr/bin/env python3
"""Generates career/data/golfer_roster.json: a FICTIONAL, sound-alike roster (in the spirit of the old Pro Evolution
Soccer licence-free names). Names are deliberately altered so none is a real person; ratings are game-estimated
(40-100), not real statistics. Deterministic. The list is ordered roughly strongest first."""
import json, random

# (first, last, nationality) strongest first. All invented sound-alikes.
NAMES = """
Scotty|Sheffler|USA
Rory|McKillroy|Northern Ireland
Jon|Rahmos|Spain
Xandre|Shaufelle|USA
Viktor|Hoveland|Norway
Colin|Morrikawa|USA
Ludwig|Aaberg|Sweden
Brysen|De Chambeau|USA
Tommy|Fleetwude|England
Mat|Fitzpatrik|England
Jordie|Speith|USA
Justin|Thomaz|USA
Patrik|Cantley|USA
Hideki|Matsuyami|Japan
Tyrel|Hatten|England
Shaun|Lowrie|Ireland
Sam|Burnes|USA
Windham|Clarke|USA
Toni|Finnau|USA
Max|Homer|USA
Dustin|Jonson|USA
Brooks|Kepka|USA
Cameron|Youngs|USA
Brian|Harmon|USA
Russel|Hendley|USA
Seb|Strakka|Austria
Robbie|MacEntire|Scotland
Tom|Kimm|South Korea
Sungjae|Imm|South Korea
Si Wu|Kimm|South Korea
Adam|Scotts|Australia
Cam|Smyth|Australia
Jayson|Dey|Australia
Min Wu|Leigh|Australia
Cory|Connors|Canada
Nick|Tayler|Canada
McKenzie|Hughs|Canada
Joaquin|Nieman|Chile
Keegen|Bradly|USA
Ricky|Fowlor|USA
Justin|Rowse|England
Sergio|Garza|Spain
Phil|Mickelsen|USA
Padraic|Harringdon|Ireland
Henrik|Stenzon|Sweden
Louis|Oosthuisen|South Africa
Branden|Grayce|South Africa
Charl|Schwartsel|South Africa
Ernie|Ells|South Africa
Retief|Gooson|South Africa
Christiaan|Bezuidenhaut|South Africa
Erik|van Rooijen|South Africa
Garrick|Higgoh|South Africa
Dean|Burmeister|South Africa
Thriston|Lawrance|South Africa
Emiliano|Grilo|Argentina
Angel|Cabrerra|Argentina
Abraham|Anser|Mexico
Carlos|Ortis|Mexico
Camilo|Villegaz|Colombia
Sebastian|Munyoz|Colombia
Jhonattan|Vegaz|Venezuela
Fabrizio|Zanoti|Paraguay
Alejandro|Tosty|Argentina
Takumi|Kanaia|Japan
Ryo|Hisatsuni|Japan
Keita|Nakashima|Japan
Rikuya|Hoshina|Japan
Shugo|Imaheira|Japan
K.H.|Leigh|South Korea
Byeong Hoon|Ahn|South Korea
Joo Hyung|Kimm|South Korea
Zecheng|Doe|China
Carl|Yuen|China
Hao Tong|Lee|China
Jazz|Janewattanon|Thailand
Kiradech|Apibarnrat|Thailand
Sadom|Kaewkanjan|Thailand
Anirban|Lahari|India
Shubankar|Sharmah|India
Marc|Leishmun|Australia
Cameron|Davies|Australia
Lukas|Herbart|Australia
Harrison|Crow|Australia
Ryan|Foxx|New Zealand
Danny|Hillyer|New Zealand
Martin|Kaimer|Germany
Bernard|Langa|Germany
Mattie|Schmitt|Germany
Yannick|Paulus|Germany
Viktor|Perrez|France
Matthieu|Pavone|France
Romain|Langasc|France
Antoine|Rosner|France
Francesco|Molinary|Italy
Guido|Migliotzi|Italy
Matteo|Manasero|Italy
Nino|Bertasso|Italy
Bernd|Wiesburger|Austria
Thomas|Peeters|Belgium
Tomas|Detree|Belgium
Joost|Luitan|Netherlands
Rasmus|Hoygard|Denmark
Nikolai|Hoygaard|Denmark
Thorbjorn|Olsen|Denmark
Joakim B.|Hanssen|Denmark
Alex|Norren|Sweden
Sebastian|Soderburg|Sweden
Joakim|Lagergreen|Sweden
Kristian|Krog Johansen|Norway
Samy|Valmaki|Finland
Tapio|Pulkanen|Finland
Rafa|Cabrero Bellos|Spain
Adrian|Otaygui|Spain
Jorge|Campilo|Spain
Pablo|Larrazabel|Spain
Alvaro|Kiros|Spain
Dani|Willet|England
Lee|Westwod|England
Ian|Polter|England
Paul|Casy|England
Aron|Rye|England
Calum|Shinkwyn|England
Richie|Blandt|England
Matt|Southgait|England
Jordon|Smyth|England
Lawrie|Cantor|England
Eddy|Peperell|England
Marcus|Armitige|England
Sam|Horsfeld|England
Dan|Bradbery|England
Olly|Wilsen|England
Martyn|Layrd|Scotland
Russel|Knocks|Scotland
Ewan|Fergusson|Scotland
Conor|Symes|Scotland
Shamus|Pauer|Ireland
Tom|McKibbon|Northern Ireland
Graham|McDowall|Northern Ireland
Darran|Clark|Northern Ireland
Rhys|Enock|Wales
Stewart|Manly|Wales
Jamie|Donalson|Wales
Zack|Jonsen|USA
Web|Simpsen|USA
Garry|Woodlund|USA
Kevin|Kissner|USA
Chris|Kirke|USA
Lukas|Glovr|USA
Billy|Horshel|USA
Harris|Inglish|USA
Denny|McCarty|USA
Akshay|Batia|USA
Nick|Dunlop|USA
Erik|Coal|USA
Tayler|Moor|USA
Davis|Thomson|USA
Jake|Knapper|USA
Matt|Kucher|USA
Patrik|Reid|USA
Bubbah|Watsen|USA
Jim|Furyck|USA
Stuart|Sink|USA
Marc|Hubbart|USA
Luke|Liszt|USA
Ryan|Palmar|USA
Cam|Champs|USA
Maverik|McNeely|USA
Sahith|Thigala|USA
Chandler|Phillipps|USA
Beau|Hosler|USA
Ben|Griffen|USA
Austen|Ecroat|USA
Andrew|Puttnam|USA
Brendan|Todds|USA
Mike|Kimm|USA
J.T.|Posten|USA
Kurt|Kitiama|USA
Jayson|Kokrack|USA
Mike|Weirr|Canada
Tayler|Pendrit|Canada
Adam|Hadwen|Canada
Ben|Silvermann|Canada
""".strip().splitlines()

FIRST = ["Alden","Bram","Cato","Dario","Emric","Fenn","Galen","Hollis","Ivo","Jarek","Kellan","Lorcan","Marek","Niall","Orsin","Pavel","Rafe","Soren","Ulric","Viggo","Wystan","Zane","Ansel","Bastian","Corin","Dmitri","Elio","Gideon","Hadrian","Joss","Kasper","Leif","Milos","Nestor","Osric","Rowan","Silas","Tobin","Valen","Wendel"]
LAST = ["Varga","Holm","Okafor","Marchetti","Tanaka","Brandt","Delacroix","Ekstrom","Faulkner","Haldane","Iversen","Jankowski","Kovac","Lemaire","Moretti","Nakamura","Ostrander","Pettigrew","Quintero","Rasmussen","Sandoval","Thackeray","Umbach","Vasquez","Whitlock","Yamada","Zielinski","Ashdown","Bellamy","Castellan","Dunmore","Eriksen","Fairweather","Hargrove","Ivanov","Jorgensen","Kingsley","Lockhart","Montrose","Northcott"]
NATS = ["England","Scotland","Ireland","Wales","USA","Canada","Australia","Spain","Sweden","Norway","Denmark","Germany","France","Italy","Japan","South Korea","South Africa","Argentina","Chile","New Zealand"]

def main():
    rng = random.Random(20261110)
    golfers = []
    used = set()
    total_named = len(NAMES)
    total = 260
    for i in range(total):
        if i < total_named:
            f, l, n = NAMES[i].split("|")
            kind = "sound_alike"
        else:
            while True:
                f, l, n = rng.choice(FIRST), rng.choice(LAST), rng.choice(NATS)
                if "%s %s" % (f, l) not in used:
                    break
            kind = "generic"
        used.add("%s %s" % (f, l))
        t = i / float(total - 1)
        rating = round(98 - 52 * (t ** 0.85) + rng.uniform(-1.8, 1.8), 1)
        golfers.append({"id": "g%03d" % (i + 1), "name": "%s %s" % (f, l), "nationality": n, "age": rng.randint(21, 46),
                        "rating": max(40.0, min(100.0, rating)), "consistency": round(rng.uniform(0.4, 0.92), 2),
                        "initial_rank": i + 1, "kind": kind})
    doc = {"dataset": {"id": "sound_alike_v1", "version": 1, "placeholder": False, "fictional": True,
           "source": "Invented sound-alike names (not real people, no real statistics); a licensed real roster can replace this file later.",
           "snapshot_date": "2026-11-10", "ratings": "game-estimated (40-100)"}, "golfers": golfers}
    with open("career/data/golfer_roster.json", "w") as fh:
        json.dump(doc, fh, indent=0, ensure_ascii=False)
    print(len(golfers), "golfers,", total_named, "sound-alike")

main()
