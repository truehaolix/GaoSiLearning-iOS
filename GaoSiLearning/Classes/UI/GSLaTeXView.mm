#import "GSLaTeXView.h"
#import "GSMathFormatUtil.h"

@interface GSLaTeXView ()
@property (nonatomic, strong) WKWebView *webView;
@end

@implementation GSLaTeXView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
        _webView.navigationDelegate = self;
        _webView.opaque = NO;
        _webView.backgroundColor = [UIColor clearColor];
        _webView.scrollView.backgroundColor = [UIColor clearColor];
        _webView.scrollView.scrollEnabled = NO;
        _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_webView];
    }
    return self;
}

- (void)renderLaTeXContent:(NSString *)content {
    self.content = content ?: @"";
    NSString *fallbackContent = [GSMathFormatUtil formatString:content ?: @""];

    // 转义 HTML 换行与特殊字符
    NSString *escapedFallback = [fallbackContent stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escapedFallback = [escapedFallback stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escapedFallback = [escapedFallback stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escapedFallback = [escapedFallback stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"];

    NSString *html = [NSString stringWithFormat:
        @"<!DOCTYPE html>"
        @"<html>"
        @"<head>"
        @"<meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no'>"
        @"<link rel='stylesheet' href='https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css'>"
        @"<script defer src='https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js'></script>"
        @"<script defer src='https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js'></script>"
        @"<style>"
        @"  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; font-size: 15px; line-height: 1.6; color: #333333; margin: 0; padding: 4px 0; background: transparent; word-break: break-word; }"
        @"  .katex { font-size: 1.05em; }"
        @"</style>"
        @"</head>"
        @"<body>"
        @"<div id='katex-content' style='display:none;'>%@</div>"
        @"<div id='fallback-content'>%@</div>"
        @"<script>"
        @"  document.addEventListener('DOMContentLoaded', function() {"
        @"    if (typeof renderMathInElement !== 'undefined') {"
        @"      try {"
        @"        var el = document.getElementById('katex-content');"
        @"        renderMathInElement(el, {"
        @"          delimiters: ["
        @"            {left: '$$', right: '$$', display: true},"
        @"            {left: '$', right: '$', display: false}"
        @"          ]"
        @"        });"
        @"        el.style.display = 'block';"
        @"        document.getElementById('fallback-content').style.display = 'none';"
        @"      } catch(e) {}"
        @"    }"
        @"    setTimeout(function() {"
        @"      window.location.hash = '#height=' + document.body.scrollHeight;"
        @"    }, 100);"
        @"  });"
        @"</script>"
        @"</body>"
        @"</html>", content ?: @"", escapedFallback];

    [_webView loadHTMLString:html baseURL:nil];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [webView evaluateJavaScript:@"document.body.scrollHeight" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if ([result isKindOfClass:[NSNumber class]]) {
            CGFloat h = [result floatValue];
            if (self.onHeightChanged) {
                self.onHeightChanged(h);
            }
        }
    }];
}

@end
