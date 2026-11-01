package editor

enum Mode i32 {
    Normal
    Insert
    Command
    Search
    VisualCharacter
    VisualLine
    VisualBlock
}

enum RegisterKind {
    Characterwise
    Linewise
    Blockwise
}

enum PickerKind {
    None
    Files
    ProjectSearch
    Buffers
}

enum SearchKind {
    Files
    Text
}

// Telia has no character literals. Keep raw ASCII values at this boundary.
const ByteNul u8 = 0
const ByteTab u8 = 9
const ByteLF u8 = 10
const ByteCR u8 = 13
const ByteSpace u8 = 32
const ByteDelete u8 = 127
const AsciiDigitFirst u8 = 48
const AsciiDigitLast u8 = 57
const AsciiUpperFirst u8 = 65
const AsciiUpperLast u8 = 90
const AsciiLowerFirst u8 = 97
const AsciiLowerLast u8 = 122
const AsciiCaseOffset u8 = 32
const Utf8ContinuationFirst u8 = 128
const Utf8ContinuationLimit u8 = 192
const TabWidth u64 = 4
const CodePointTab u32 = 9
const CodePointSpace u32 = 32
const CodePointDelete u32 = 127
const CodePointQuestion u32 = 63

const KeyCtrlB u8 = 2
const KeyCtrlC u8 = 3
const KeyCtrlF u8 = 6
const KeyBackspace u8 = 8
const KeyTab u8 = ByteTab
const KeyCtrlJ u8 = ByteLF
const KeyCtrlK u8 = 11
const KeyEnter u8 = ByteCR
const KeyCtrlP u8 = 16
const KeyCtrlR u8 = 18
const KeyCtrlV u8 = 22
const KeyCtrlW u8 = 23
const KeyEscape u8 = 27
const KeyCtrlCaret u8 = 30
const KeyDelete u8 = ByteDelete

const KeyDollar u8 = 36
const KeyPlus u8 = 43
const KeyMinus u8 = 45
const KeySlash u8 = 47
const KeyZero u8 = 48
const KeyColon u8 = 58
const KeyLess u8 = 60
const KeyEqual u8 = 61
const KeyGreater u8 = 62
const KeyUpperA u8 = 65
const KeyUpperG u8 = 71
const KeyUpperI u8 = 73
const KeyUpperN u8 = 78
const KeyUpperO u8 = 79
const KeyUpperP u8 = 80
const KeyUpperV u8 = 86
const KeyLowerA u8 = 97
const KeyLowerB u8 = 98
const KeyLowerC u8 = 99
const KeyLowerD u8 = 100
const KeyLowerG u8 = 103
const KeyLowerH u8 = 104
const KeyLowerI u8 = 105
const KeyLowerJ u8 = 106
const KeyLowerK u8 = 107
const KeyLowerL u8 = 108
const KeyLowerN u8 = 110
const KeyLowerO u8 = 111
const KeyLowerP u8 = 112
const KeyLowerS u8 = 115
const KeyLowerU u8 = 117
const KeyLowerV u8 = 118
const KeyLowerW u8 = 119
const KeyLowerX u8 = 120
const KeyLowerY u8 = 121

const ByteQuestion u8 = 63
const ByteUnderscore u8 = 95
const ByteSlash u8 = 47
const ByteDash u8 = 45
const ByteColon u8 = 58
const ByteEscape u8 = 27
const ByteLeftBracket u8 = 91
const ByteUpperO u8 = 79
const ByteTilde u8 = 126
const ByteZero u8 = 48
const ByteOne u8 = 49
const ByteTwo u8 = 50
const AnsiFinalFirst u8 = 64
const AnsiFinalLast u8 = 126
const MaxEscapeBytes u64 = 64
const AnsiArrowUp u8 = 65
const AnsiArrowDown u8 = 66
const AnsiArrowRight u8 = 67
const AnsiArrowLeft u8 = 68
const AnsiHome u8 = 72
const AnsiEnd u8 = 70
