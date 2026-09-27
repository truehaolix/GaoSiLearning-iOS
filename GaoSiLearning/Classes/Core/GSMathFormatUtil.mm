//
//  GSMathFormatUtil.mm
//  GaoSiLearning
//
//  数学与理科表达式规范化渲染工具类实现
//

#import "GSMathFormatUtil.h"

@implementation GSMathFormatUtil

+ (NSString *)formatString:(NSString *)rawText {
    if (!rawText || rawText.length == 0) return @"";

    NSMutableString *s = [rawText mutableCopy];

    // 1. 替换核心结论醒目标注 \boxed{...} -> 【...】
    NSRegularExpression *boxedRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\boxed\\{([^\\{\\}]*(?:\\{[^\\{\\}]*\\}[^\\{\\}]*)*)\\}" options:0 error:nil];
    [boxedRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"【$1】"];

    // 2. 递归替换分式 \frac{num}{den} 与 \dfrac{num}{den}
    NSRegularExpression *fracRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(?:d)?frac\\{([^\\{\\}]*(?:\\{[^\\{\\}]*\\}[^\\{\\}]*)*)\\}\\{([^\\{\\}]*(?:\\{[^\\{\\}]*\\}[^\\{\\}]*)*)\\}" options:0 error:nil];
    NSInteger maxDepth = 5;
    while (maxDepth > 0) {
        NSTextCheckingResult *match = [fracRegex firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (!match) break;

        NSString *numRaw = [[s substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *denRaw = [[s substringWithRange:[match rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        NSString *num = [self formatString:numRaw];
        NSString *den = [self formatString:denRaw];

        BOOL numNeedsP = [self exprNeedsParens:num];
        BOOL denNeedsP = [self exprNeedsParens:den];

        NSString *numW = numNeedsP ? [NSString stringWithFormat:@"(%@)", num] : num;
        NSString *denW = denNeedsP ? [NSString stringWithFormat:@"(%@)", den] : den;

        NSString *replacement = [NSString stringWithFormat:@"%@ / %@", numW, denW];
        [s replaceCharactersInRange:match.range withString:replacement];
        maxDepth--;
    }

    // 3. 根号处理 \sqrt[3]{...} 与 \sqrt{...}
    NSRegularExpression *cbrtRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\sqrt\\[3\\]\\{([^\\{\\}]+)\\}" options:0 error:nil];
    [cbrtRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"∛($1)"];

    NSRegularExpression *sqrtRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\sqrt\\{([^\\{\\}]+)\\}" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *sqrtMatches = [[sqrtRegex matchesInString:s options:0 range:NSMakeRange(0, s.length)] reverseObjectEnumerator].allObjects;
    for (NSTextCheckingResult *m in sqrtMatches) {
        NSString *inner = [[s substringWithRange:[m rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *rep = (inner.length <= 2 && ![inner containsString:@"+"] && ![inner containsString:@"-"]) ?
            [NSString stringWithFormat:@"√%@", inner] :
            [NSString stringWithFormat:@"√(%@)", inner];
        [s replaceCharactersInRange:m.range withString:rep];
    }

    // 4. 幂与上标处理（如 x^2, x^{3}, e^x 等）
    NSDictionary<NSString *, NSString *> *superscriptMap = @{
        @"0": @"⁰", @"1": @"¹", @"2": @"²", @"3": @"³", @"4": @"⁴",
        @"5": @"⁵", @"6": @"⁶", @"7": @"⁷", @"8": @"⁸", @"9": @"⁹",
        @"+": @"⁺", @"-": @"⁻", @"=": @"⁼", @"(": @"⁽", @")": @"⁾",
        @"n": @"ⁿ", @"i": @"ⁱ", @"x": @"ˣ", @"y": @"ʸ", @"a": @"ᵃ", @"b": @"ᵇ"
    };

    NSRegularExpression *supBraceRegex = [NSRegularExpression regularExpressionWithPattern:@"\\^\\{([0-9+\\-nixyab]+)\\}" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *supBMatches = [[supBraceRegex matchesInString:s options:0 range:NSMakeRange(0, s.length)] reverseObjectEnumerator].allObjects;
    for (NSTextCheckingResult *m in supBMatches) {
        NSString *content = [s substringWithRange:[m rangeAtIndex:1]];
        NSMutableString *rep = [NSMutableString string];
        for (NSUInteger i = 0; i < content.length; i++) {
            NSString *ch = [content substringWithRange:NSMakeRange(i, 1)];
            [rep appendString:superscriptMap[ch] ?: ch];
        }
        [s replaceCharactersInRange:m.range withString:rep];
    }

    NSRegularExpression *supSingleRegex = [NSRegularExpression regularExpressionWithPattern:@"\\^([0-9+\\-nixyab])" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *supSMatches = [[supSingleRegex matchesInString:s options:0 range:NSMakeRange(0, s.length)] reverseObjectEnumerator].allObjects;
    for (NSTextCheckingResult *m in supSMatches) {
        NSString *ch = [s substringWithRange:[m rangeAtIndex:1]];
        NSString *rep = superscriptMap[ch] ?: [NSString stringWithFormat:@"^%@", ch];
        [s replaceCharactersInRange:m.range withString:rep];
    }

    // 5. 下标处理（如 x_1, x_{2}, a_n 等）
    NSDictionary<NSString *, NSString *> *subscriptMap = @{
        @"0": @"₀", @"1": @"₁", @"2": @"₂", @"3": @"₃", @"4": @"₄",
        @"5": @"₅", @"6": @"₆", @"7": @"₇", @"8": @"₈", @"9": @"₉",
        @"+": @"₊", @"-": @"₋", @"=": @"₌", @"(": @"₍", @")": @"₎",
        @"a": @"ₐ", @"e": @"ₑ", @"i": @"ᵢ", @"j": @"ⱼ", @"k": @"ₖ",
        @"m": @"ₘ", @"n": @"ₙ", @"p": @"ₚ", @"r": @"ᵣ", @"s": @"ₛ", @"t": @"ₜ", @"x": @"ₓ"
    };

    NSRegularExpression *subBraceRegex = [NSRegularExpression regularExpressionWithPattern:@"_\\{([0-9aeijkmptx]+)\\}" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *subBMatches = [[subBraceRegex matchesInString:s options:0 range:NSMakeRange(0, s.length)] reverseObjectEnumerator].allObjects;
    for (NSTextCheckingResult *m in subBMatches) {
        NSString *content = [s substringWithRange:[m rangeAtIndex:1]];
        NSMutableString *rep = [NSMutableString string];
        for (NSUInteger i = 0; i < content.length; i++) {
            NSString *ch = [content substringWithRange:NSMakeRange(i, 1)];
            [rep appendString:subscriptMap[ch] ?: ch];
        }
        [s replaceCharactersInRange:m.range withString:rep];
    }

    NSRegularExpression *subSingleRegex = [NSRegularExpression regularExpressionWithPattern:@"_([0-9aeijkmptx])" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *subSMatches = [[subSingleRegex matchesInString:s options:0 range:NSMakeRange(0, s.length)] reverseObjectEnumerator].allObjects;
    for (NSTextCheckingResult *m in subSMatches) {
        NSString *ch = [s substringWithRange:[m rangeAtIndex:1]];
        NSString *rep = subscriptMap[ch] ?: [NSString stringWithFormat:@"_%@", ch];
        [s replaceCharactersInRange:m.range withString:rep];
    }

    // 6. 常用数学与理科符号替换
    NSArray<NSArray<NSString *> *> *symbols = @[
        @[@"\\\\pm\\b", @"±"],
        @[@"\\\\mp\\b", @"∓"],
        @[@"\\\\times\\b", @"×"],
        @[@"\\\\div\\b", @"÷"],
        @[@"\\\\cdot\\b", @"·"],
        @[@"\\\\neq\\b|\\\\ne\\b", @"≠"],
        @[@"\\\\leq\\b|\\\\le\\b", @"≤"],
        @[@"\\\\geq\\b|\\\\ge\\b", @"≥"],
        @[@"\\\\approx\\b", @"≈"],
        @[@"\\\\equiv\\b", @"≡"],
        @[@"\\\\infty\\b", @"∞"],
        @[@"\\\\propto\\b", @"∝"],
        @[@"\\\\perp\\b", @"⊥"],
        @[@"\\\\parallel\\b", @"∥"],
        @[@"\\\\triangle\\b|\\\\bigtriangleup\\b", @"△"],
        @[@"\\\\angle\\b", @"∠"],
        @[@"\\\\degree\\b|\\^\\\\circ\\b", @"°"],
        @[@"\\\\implies\\b|\\\\Rightarrow\\b", @"⇒"],
        @[@"\\\\iff\\b|\\\\Leftrightarrow\\b", @"⇔"],
        @[@"\\\\to\\b|\\\\rightarrow\\b", @"→"],
        @[@"\\\\leftarrow\\b", @"←"],
        @[@"\\\\in\\b", @"∈"],
        @[@"\\\\notin\\b", @"∉"],
        @[@"\\\\subset\\b", @"⊂"],
        @[@"\\\\subseteq\\b", @"⊆"],
        @[@"\\\\supset\\b", @"⊃"],
        @[@"\\\\supseteq\\b", @"⊇"],
        @[@"\\\\cup\\b", @"∪"],
        @[@"\\\\cap\\b", @"∩"],
        @[@"\\\\emptyset\\b|\\\\varnothing\\b", @"∅"],
        @[@"\\\\forall\\b", @"∀"],
        @[@"\\\\exists\\b", @"∃"],
        @[@"\\\\alpha\\b", @"α"],
        @[@"\\\\beta\\b", @"β"],
        @[@"\\\\gamma\\b", @"γ"],
        @[@"\\\\delta\\b", @"δ"],
        @[@"\\\\theta\\b", @"θ"],
        @[@"\\\\lambda\\b", @"λ"],
        @[@"\\\\mu\\b", @"μ"],
        @[@"\\\\pi\\b", @"π"],
        @[@"\\\\rho\\b", @"ρ"],
        @[@"\\\\sigma\\b", @"σ"],
        @[@"\\\\tau\\b", @"τ"],
        @[@"\\\\phi\\b", @"φ"],
        @[@"\\\\omega\\b", @"ω"],
        @[@"\\\\Delta\\b", @"Δ"],
        @[@"\\\\Sigma\\b", @"Σ"],
        @[@"\\\\Omega\\b", @"Ω"],
        @[@"\\\\sin\\b", @"sin"],
        @[@"\\\\cos\\b", @"cos"],
        @[@"\\\\tan\\b", @"tan"],
        @[@"\\\\log\\b", @"log"],
        @[@"\\\\ln\\b", @"ln"],
        @[@"\\\\qquad\\b", @"  "],
        @[@"\\\\quad\\b", @" "],
        @[@"\\\\,|\\\\;|\\\\!", @" "],
        @[@"\\\\left\\(", @"("],
        @[@"\\\\right\\)", @")"],
        @[@"\\\\left\\[", @"["],
        @[@"\\\\right\\]", @"]"],
        @[@"\\\\left\\{", @"{"],
        @[@"\\\\right\\}", @"}"],
        @[@"\\\\\\{", @"{"],
        @[@"\\\\\\}", @"}"],
        @[@"\\\\dots\\b|\\\\cdots\\b|\\\\ldots\\b", @"..."]
    ];

    for (NSArray<NSString *> *pair in symbols) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pair[0] options:0 error:nil];
        if (re) {
            [re replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:pair[1]];
        }
    }

    // 7. 文本修饰解包 \text{...}, \mathbf{...}, \mathrm{...}
    NSRegularExpression *textRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(?:text|mathbf|mathrm|mathit)\\{([^\\{\\}]+)\\}" options:0 error:nil];
    [textRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1"];

    // 8. 向量符号 \vec{a} -> a⃗
    NSRegularExpression *vecRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\vec\\{([a-zA-Z])\\}" options:0 error:nil];
    [vecRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1⃗"];

    NSRegularExpression *arrowRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\overrightarrow\\{([a-zA-Z]+)\\}" options:0 error:nil];
    [arrowRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1⃗"];

    // 9. 剥除 LaTeX 公式界定符 $$ 与 $
    [s replaceOccurrencesOfString:@"$$" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"$" withString:@"" options:0 range:NSMakeRange(0, s.length)];

    // 10. 清理残留的多余反斜杠控制符
    NSRegularExpression *cleanupRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\([a-zA-Z]+)" options:0 error:nil];
    [cleanupRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1"];

    NSRegularExpression *spaceRegex = [NSRegularExpression regularExpressionWithPattern:@"[ ]{2,}" options:0 error:nil];
    [spaceRegex replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];

    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (BOOL)exprNeedsParens:(NSString *)expr {
    if ([expr hasPrefix:@"("] && [expr hasSuffix:@")"]) return NO;
    return [expr containsString:@"+"] || [expr containsString:@"-"] || [expr containsString:@" "];
}

+ (void)applyToLabel:(UILabel *)label text:(NSString *)text {
    if (!label) return;
    label.text = [self formatString:text];
}

@end
