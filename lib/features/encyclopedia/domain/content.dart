// Short editorial summaries; references were checked on 2026-11-05.
// Samples preserve the spelling of the sign, not a transliteration algorithm.
typedef EncyclopediaSource = ({String title, String url});
typedef EncyclopediaItem = ({String name, String sample, String explanation});
const alphabetSource = (
  title: 'Плетнёва, Кравецкий: алфавит',
  url:
      'https://azbyka.ru/otechnik/Aleksandr-Kraveckij/uchebnoe-rukovodstvo-po-tserkovnoslavjanskomu-jazyku/1',
);
const marksSource = (
  title: 'Плетнёва, Кравецкий: надстрочные знаки',
  url:
      'https://azbyka.ru/otechnik/Aleksandr-Kraveckij/uchebnoe-rukovodstvo-po-tserkovnoslavjanskomu-jazyku/2_4',
);
const numbersSource = (
  title: 'Плетнёва, Кравецкий: запись чисел',
  url:
      'https://azbyka.ru/otechnik/Aleksandr-Kraveckij/uchebnoe-rukovodstvo-po-tserkovnoslavjanskomu-jazyku/3',
);
const signsTableSource = (
  title: 'Надстрочные знаки: таблица',
  url: 'https://azbyka.ru/cerkovnoslavyanskij-yazyk-v-tablicax',
);
const glagoliticSource = (
  title: 'Unicode: глаголические буквы',
  url: 'https://www.unicode.org/charts/PDF/U2C00.pdf',
);

const cyrillicLetters = <(String, String)>[
  ('А а', 'Аз'),
  ('Б б', 'Буки'),
  ('В в', 'Веди'),
  ('Г г', 'Глаголь'),
  ('Д д', 'Добро'),
  ('Е е є', 'Есть'),
  ('Ж ж', 'Живете'),
  ('Ѕ ѕ', 'Зело'),
  ('З з', 'Земля'),
  ('И и', 'Иже'),
  ('І і Ї ї', 'И'),
  ('К к', 'Како'),
  ('Л л', 'Люди'),
  ('М м', 'Мыслете'),
  ('Н н', 'Наш'),
  ('О о Ѻ ѻ', 'Он'),
  ('П п', 'Покой'),
  ('Р р', 'Рцы'),
  ('С с', 'Слово'),
  ('Т т', 'Твердо'),
  ('Оу ᲂу Ꙋ ꙋ', 'Ук'),
  ('Ф ф', 'Ферт'),
  ('Х х', 'Хер'),
  ('Ѿ ѿ', 'От'),
  ('Ц ц', 'Цы'),
  ('Ч ч', 'Червь'),
  ('Ш ш', 'Ша'),
  ('Щ щ', 'Ща'),
  ('Ъ ъ', 'Ер'),
  ('Ы ы', 'Еры'),
  ('Ь ь', 'Ерь'),
  ('Ѣ ѣ', 'Ять'),
  ('Ю ю', 'Ю'),
  ('Ꙗ ꙗ', 'Я'),
  ('Ѡ ѡ', 'Омега'),
  ('Ѧ ѧ', 'Юс малый'),
  ('Ѯ ѯ', 'Кси'),
  ('Ѱ ѱ', 'Пси'),
  ('Ѳ ѳ', 'Фита'),
  ('Ѵ ѵ', 'Ижица'),
];

// A first set of examples, not a claim that the historical alphabet has 24 letters.
const glagoliticLetters = <(String, String)>[
  ('Ⰰ ⰰ', 'Аз'),
  ('Ⰱ ⰱ', 'Буки'),
  ('Ⰲ ⰲ', 'Веди'),
  ('Ⰳ ⰳ', 'Глаголь'),
  ('Ⰴ ⰴ', 'Добро'),
  ('Ⰵ ⰵ', 'Есть'),
  ('Ⰶ ⰶ', 'Живете'),
  ('Ⰷ ⰷ', 'Зело'),
  ('Ⰸ ⰸ', 'Земля'),
  ('Ⰽ ⰽ', 'Како'),
  ('Ⰾ ⰾ', 'Люди'),
  ('Ⰿ ⰿ', 'Мыслете'),
  ('Ⱀ ⱀ', 'Наш'),
  ('Ⱁ ⱁ', 'Он'),
  ('Ⱂ ⱂ', 'Покой'),
  ('Ⱃ ⱃ', 'Рцы'),
  ('Ⱄ ⱄ', 'Слово'),
  ('Ⱅ ⱅ', 'Твердо'),
  ('Ⱆ ⱆ', 'Ук'),
  ('Ⱇ ⱇ', 'Ферт'),
  ('Ⱈ ⱈ', 'Хер'),
  ('Ⱌ ⱌ', 'Цы'),
  ('Ⱍ ⱍ', 'Червь'),
  ('Ⱎ ⱎ', 'Ша'),
];

const diacriticItems = <EncyclopediaItem>[
  (
    name: 'Острое ударение — оксия',
    sample: 'а́',
    explanation:
        'Указывает ударную гласную. Различие начертаний ударения само по себе не означает разной силы произношения.',
  ),
  (
    name: 'Тяжёлое ударение — вария',
    sample: 'а̀',
    explanation:
        'Обычно употребляется на ударной гласной в конце слова. При некоторых следующих безударных словах сохраняется острое ударение.',
  ),
  (
    name: 'Облечённое ударение — камора',
    sample: 'а̑',
    explanation:
        'Помогает различать одинаково звучащие грамматические формы, например единственного и множественного числа.',
  ),
  (
    name: 'Звательце',
    sample: 'а҆',
    explanation:
        'Знак придыхания над начальной гласной. В современном церковном чтении отдельного звука не обозначает.',
  ),
  (
    name: 'Исо',
    sample: 'а҆́',
    explanation: 'Сочетание звательца и острого ударения над одной гласной.',
  ),
  (
    name: 'Апостроф',
    sample: 'а҆̀',
    explanation:
        'Сочетание звательца и тяжёлого ударения. Это название надстрочного сочетания, а не знак обычной клавиатуры.',
  ),
  (
    name: 'Простое титло',
    sample: '◌҃',
    explanation:
        'Обозначает сокращённое написание слова; также используется над буквами в записи чисел.',
  ),
  (
    name: 'Буквотитла и покрытие',
    sample: '◌ⷭ҇',
    explanation:
        'Буква выносится над строкой. Некоторые выносные буквы сопровождаются покрытием. На образце показана надстрочная «с» с покрытием.',
  ),
];

const numberItems = <EncyclopediaItem>[
  (
    name: 'Буквы под титлом',
    sample: 'а҃ · в҃ · і҃',
    explanation:
        'В буквенной записи эти знаки обозначают 1, 2 и 10. Числовое значение имеет не каждая буква азбуки.',
  ),
  (
    name: 'Знак тысячи',
    sample: '҂',
    explanation:
        'Ставится перед буквой с числовым значением и указывает на тысячи. Он располагается у строки, а не над буквой.',
  ),
  (
    name: 'Примеры тысяч',
    sample: '҂а҃ · ҂в҃ · ҂і҃',
    explanation:
        'Соответственно: 1000, 2000 и 10 000. Знак тысячи и титло выполняют разные функции.',
  ),
];
