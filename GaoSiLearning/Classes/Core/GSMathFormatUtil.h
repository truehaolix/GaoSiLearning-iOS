//
//  GSMathFormatUtil.h
//  GaoSiLearning
//
//  数学与理科表达式规范化渲染工具类
//  将大模型 / OCR 返回的标准 LaTeX 语法（如 \frac{a}{b}、\sqrt{x}、x^2、\boxed{} 等）
//  转化为移动端 iOS 界面（UILabel / UIButton）可直接自然优雅阅读的数学图文格式。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSMathFormatUtil : NSObject

/**
 * 将输入文本规范化格式化为标准易读的自然数学图文格式
 * 递归解析分式、根号、上下标、特殊希腊符号、逻辑符号、向量及解包公式定界符
 */
+ (NSString *)formatString:(nullable NSString *)rawText;

/**
 * 针对 UILabel 的安全直接赋值，自动进行数学格式化
 */
+ (void)applyToLabel:(nullable UILabel *)label text:(nullable NSString *)text;

@end

NS_ASSUME_NONNULL_END
