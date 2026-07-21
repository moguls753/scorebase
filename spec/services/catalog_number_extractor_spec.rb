require "rails_helper"

RSpec.describe CatalogNumberExtractor do
  # Oracle cases: title + external_url -> expected catalog (nil/"" means reject).
  {
    "www-form encoding" => [
      "Magnificat Fugue",
      "https://imslp.org/wiki/Magnificat+Fugue%2C+P.257+%28Pachelbel%2C+Johann%29",
      "P.257"
    ],
    "underscore encoding" => [
      "14 Canons",
      "https://imslp.org/wiki/14_Canons,_BWV_1087_(Bach,_Johann_Sebastian)",
      "BWV 1087"
    ],
    "comma-in-title anchors on stored title" => [
      "Lobt Gott, ihr Christen, allzugleich",
      "https://imslp.org/wiki/Lobt+Gott%2C+ihr+Christen%2C+allzugleich%2C+BWV+609+%28Bach%2C+Johann+Sebastian%29",
      "BWV 609"
    ],
    "full work-title" => [
      "Keyboard Sonata in C major",
      "https://imslp.org/wiki/Keyboard+Sonata+in+C+major%2C+HWV+577+%28Handel%2C+George+Frideric%29",
      "HWV 577"
    ],
    "Deutsch number" => [
      "12 Ecossaises",
      "https://imslp.org/wiki/12_Ecossaises,_D.299_(Schubert,_Franz)",
      "D.299"
    ],
    "colon-bearing Hoboken catalog" => [
      "12 English Ballads",
      "https://imslp.org/wiki/12_English_Ballads,_Hob.XXVIa:Anh.a_2_(Haydn,_Joseph)",
      "Hob.XXVIa:Anh.a 2"
    ],
    "range-form catalog" => [
      "12 Fantasias for Flute without Bass",
      "https://imslp.org/wiki/12_Fantasias_for_Flute_without_Bass,_TWV_40:2-13_(Telemann,_Georg_Philipp)",
      "TWV 40:2-13"
    ],
    "word-suffix disambiguator" => [
      "2 Duos for Violin and Cello",
      "https://imslp.org/wiki/2_Duos_for_Violin_and_Cello,_Book_2_(Bohrer,_Antoine)",
      "Book 2"
    ],
    "title is literally parens" => [
      "( )",
      "https://imslp.org/wiki/(_),_Op.1_(Topete_Galv%C3%A1n,_Luis)",
      "Op.1"
    ],
    "leading parenthetical in title survives" => [
      "(Ver)suche Frieden...",
      "https://imslp.org/wiki/(Ver)suche_Frieden...,_Op.133_(Hirschfeld,_C._Ren%C3%A9)",
      "Op.133"
    ],
    "already-numbered title -> skip" => [
      "10 Chants populaires Lettons, Op.29",
      "https://imslp.org/wiki/10_Chants_populaires_Lettons,_Op.29_(V%C4%ABtols,_J%C4%81zeps)",
      nil
    ],
    "partial-prefix title -> skip" => [
      "Keyboard Sonata",
      "https://imslp.org/wiki/Keyboard+Sonata+in+G+minor%2C+HWV+580+%28Handel%2C+George+Frideric%29",
      nil
    ],
    "mislabeled row (title not a prefix) -> skip" => [
      "Keyboard Sonata in E minor",
      "https://imslp.org/wiki/Aus+der+Tiefe+rufe+ich%2C+BWV+745+%28Bach%2C+Johann+Sebastian%29",
      nil
    ],
    "translated/alt title -> skip" => [
      "Two pieces, a song and a waltz",
      "https://imslp.org/wiki/1_Lied_and_1_Walzer_(Lang,_Josephine)",
      nil
    ],
    "no-catalog IMSLP work -> skip" => [
      "10 Compositions for Organ",
      "https://imslp.org/wiki/10_Compositions_for_Organ_(Grace,_Harvey)",
      nil
    ],
    "non-catalog-shaped suffix -> skip" => [
      "Prelude",
      "https://imslp.org/wiki/Prelude,_Selections_(Bach,_Johann_Sebastian)",
      nil
    ],
    "non-imslp host (CPDL) -> reject" => [
      "'High' Evening Service",
      "https://www1.cpdl.org/wiki/index.php/%27High%27+Evening+Service+%28Richard+Farrant%29",
      nil
    ],
    "non-imslp blank url -> nil" => [
      "Tre Sonatine - No.1 - Rondo, op. 71",
      "",
      nil
    ]
  }.each do |name, (title, url, expected)|
    it "#{name}: #{expected.inspect}" do
      result = described_class.extract(title, url)
      expected.present? ? expect(result).to(eq(expected)) : expect(result).to(be_nil)
    end
  end
end
