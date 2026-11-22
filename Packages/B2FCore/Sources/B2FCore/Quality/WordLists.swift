import Foundation

/// Static lexical resources for the quality filter. Lists are intentionally
/// compact: they catch the low-value words that dominate textbook OCR output.
/// They can be extended or replaced per language via `VocabularyQualityFilter.Configuration`.
public enum WordLists {

    public static func stopWords(for language: StudyLanguage) -> Set<String> {
        switch language {
        case .english: return englishStopWords
        case .german: return germanStopWords
        case .french: return frenchStopWords
        case .spanish: return spanishStopWords
        case .persian: return persianStopWords
        case .arabic: return arabicStopWords
        }
    }

    /// Very frequent content words that rarely deserve a card for B1+ learners.
    public static func veryCommonWords(for language: StudyLanguage) -> Set<String> {
        language == .english ? englishVeryCommon : []
    }

    public static let englishStopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "so", "of", "to", "in", "on", "at", "by",
        "for", "with", "about", "against", "between", "into", "through", "during", "before", "after", "above",
        "below", "from", "up", "down", "out", "off", "over", "under", "again", "further", "once", "here",
        "there", "when", "where", "why", "how", "all", "any", "both", "each", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "than", "too", "very", "can", "will", "just",
        "should", "now", "i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "yourself", "yourselves", "he", "him", "his", "himself", "she", "her", "hers", "herself", "it", "its",
        "itself", "they", "them", "their", "theirs", "themselves", "what", "which", "who", "whom", "this",
        "that", "these", "those", "am", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "having", "do", "does", "did", "doing", "would", "could", "ought", "i'm", "you're", "he's", "she's",
        "it's", "we're", "they're", "i've", "you've", "we've", "they've", "i'd", "you'd", "he'd", "she'd",
        "we'd", "they'd", "i'll", "you'll", "he'll", "she'll", "we'll", "they'll", "isn't", "aren't", "wasn't",
        "weren't", "hasn't", "haven't", "hadn't", "doesn't", "don't", "didn't", "won't", "wouldn't", "shan't",
        "shouldn't", "can't", "cannot", "couldn't", "mustn't", "let's", "that's", "who's", "what's", "here's",
        "there's", "when's", "where's", "why's", "how's", "also", "yes", "ok", "okay", "oh", "etc", "eg", "ie",
        "page", "unit", "lesson", "exercise", "answer", "answers", "listen", "read", "write", "complete",
        "match", "look", "ex", "p", "vs"
    ]

    public static let englishVeryCommon: Set<String> = [
        "time", "person", "year", "way", "day", "thing", "man", "world", "life", "hand", "part", "child", "eye",
        "woman", "place", "work", "week", "case", "point", "number", "group", "fact", "get", "make", "go",
        "know", "take", "see", "come", "think", "want", "give", "use", "find", "tell", "ask", "seem", "feel",
        "try", "leave", "call", "good", "new", "first", "last", "long", "great", "little", "old", "big", "high",
        "different", "small", "large", "next", "early", "young", "important", "public", "bad", "able", "people",
        "like", "said", "say", "says", "went", "got", "made", "one", "two", "three", "four", "five", "six",
        "seven", "eight", "nine", "ten", "many", "much", "well", "back", "even", "still", "may", "must",
        "might", "really", "always", "never", "often", "sometimes", "today", "yesterday", "tomorrow", "every",
        "home", "house", "school", "friend", "family", "mother", "father", "name", "book", "car", "food", "water",
        "money", "job", "city", "country", "room", "night", "morning", "boy", "girl", "dog", "cat", "talk",
        "put", "need", "help", "start", "show", "hear", "play", "run", "move", "live", "believe", "bring",
        "happen", "sit", "stand", "lose", "pay", "meet", "learn", "change", "lead", "understand", "watch",
        "follow", "stop", "speak", "open", "close", "buy", "eat", "drink", "sleep", "walk", "love", "nice",
        "happy", "sad", "yes", "thanks", "thank", "please", "sorry", "hello", "hi", "bye", "right", "left"
    ]

    /// Subset of Coxhead's Academic Word List headwords (sublists 1–3) – a strong
    /// signal for academic/exam value.
    public static let academicWords: Set<String> = [
        "analyse", "analyze", "approach", "area", "assess", "assume", "authority", "available", "benefit",
        "concept", "consist", "constitute", "context", "contract", "create", "data", "define", "derive",
        "distribute", "economy", "environment", "establish", "estimate", "evident", "export", "factor",
        "finance", "formula", "function", "identify", "income", "indicate", "individual", "interpret",
        "involve", "issue", "labour", "labor", "legal", "legislate", "major", "method", "occur", "percent",
        "period", "policy", "principle", "proceed", "process", "require", "research", "respond", "role",
        "section", "sector", "significant", "similar", "source", "specific", "structure", "theory", "vary",
        "achieve", "acquire", "administrate", "affect", "appropriate", "aspect", "assist", "category",
        "chapter", "commission", "community", "complex", "compute", "conclude", "conduct", "consequent",
        "construct", "consume", "credit", "culture", "design", "distinct", "element", "equate", "evaluate",
        "feature", "final", "focus", "impact", "injure", "institute", "invest", "item", "journal", "maintain",
        "normal", "obtain", "participate", "perceive", "positive", "potential", "previous", "primary",
        "purchase", "range", "region", "regulate", "relevant", "reside", "resource", "restrict", "secure",
        "seek", "select", "site", "strategy", "survey", "text", "tradition", "transfer", "alternative",
        "circumstance", "comment", "compensate", "component", "consent", "considerable", "constant",
        "constrain", "contribute", "convene", "coordinate", "core", "corporate", "correspond", "criteria",
        "deduce", "demonstrate", "document", "dominate", "emphasis", "ensure", "exclude", "framework", "fund",
        "illustrate", "immigrate", "imply", "initial", "instance", "interact", "justify", "layer", "link",
        "locate", "maximise", "maximize", "minor", "negate", "outcome", "partner", "philosophy", "physical",
        "proportion", "publish", "react", "register", "rely", "remove", "scheme", "sequence", "sex", "shift",
        "specify", "sufficient", "task", "technical", "technique", "technology", "valid", "volume"
    ]

    public static let germanStopWords: Set<String> = [
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "und",
        "oder", "aber", "doch", "denn", "in", "im", "an", "am", "auf", "aus", "bei", "mit", "nach", "von",
        "vom", "zu", "zum", "zur", "für", "über", "unter", "vor", "hinter", "ich", "du", "er", "sie", "es",
        "wir", "ihr", "mich", "dich", "sich", "mir", "dir", "ist", "sind", "war", "waren", "bin", "bist",
        "hat", "haben", "hatte", "nicht", "kein", "keine", "ja", "nein", "auch", "so", "wie", "was", "wer",
        "wo", "wann", "warum", "dass", "wenn", "als", "noch", "schon", "nur", "sehr", "hier", "da", "dort",
        "lektion", "seite", "übung", "aufgabe"
    ]

    public static let frenchStopWords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "et", "ou", "mais", "donc", "car", "ni",
        "à", "au", "aux", "en", "dans", "par", "pour", "sur", "sous", "avec", "sans", "chez", "je", "j", "tu",
        "il", "elle", "on", "nous", "vous", "ils", "elles", "me", "m", "te", "t", "se", "s", "lui", "leur",
        "ce", "c", "cet", "cette", "ces", "est", "sont", "était", "être", "avoir", "a", "ai", "as", "ont",
        "ne", "n", "pas", "plus", "que", "qu", "qui", "quoi", "où", "quand", "comment", "très", "aussi",
        "oui", "non", "leçon", "page", "exercice"
    ]

    public static let spanishStopWords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "lo", "y", "e", "o", "u", "pero", "sino", "de",
        "del", "a", "al", "en", "con", "por", "para", "sin", "sobre", "entre", "hasta", "desde", "yo", "tú",
        "tu", "él", "ella", "usted", "nosotros", "vosotros", "ellos", "ellas", "ustedes", "me", "te", "se",
        "nos", "os", "le", "les", "mi", "su", "sus", "es", "son", "era", "ser", "estar", "está", "están",
        "hay", "ha", "han", "no", "sí", "que", "qué", "quien", "cuando", "donde", "como", "muy", "también",
        "ya", "más", "lección", "unidad", "página", "ejercicio"
    ]

    public static let persianStopWords: Set<String> = [
        "و", "در", "به", "از", "که", "این", "آن", "با", "را", "برای", "تا", "یا", "هم", "اما", "اگر", "پس",
        "من", "تو", "او", "ما", "شما", "آنها", "است", "هست", "بود", "شد", "شود", "می", "نمی", "هر", "یک",
        "چه", "چرا", "کجا", "کی", "چگونه", "بر", "نیز", "باید", "دارد", "دارند", "کرد", "کند", "درس", "فصل",
        "صفحه", "تمرین"
    ]

    public static let arabicStopWords: Set<String> = [
        "و", "في", "من", "إلى", "على", "عن", "أن", "إن", "ان", "هذا", "هذه", "ذلك", "تلك", "التي", "الذي",
        "هو", "هي", "هم", "نحن", "أنا", "انا", "أنت", "كان", "كانت", "يكون", "لا", "لم", "لن", "ما", "مع",
        "قد", "ثم", "أو", "او", "كل", "بعد", "قبل", "حتى", "الدرس", "الوحدة", "صفحة", "تمرين"
    ]
}
