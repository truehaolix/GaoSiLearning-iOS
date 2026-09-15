#ifndef ImageProcessor_hpp
#define ImageProcessor_hpp

#import <UIKit/UIKit.h>
#include <vector>
#include <string>

struct QuestionBox {
    CGRect rect; // 归一化坐标 [0, 1]
    float confidence;
    int index;
};

#ifdef __cplusplus
class ImageProcessorCore {
public:
    static void enhanceContrastGrayscale(unsigned char* grayData, int width, int height);
    static void sauvolaBinarize(const unsigned char* grayData, unsigned char* outputBin, int width, int height, int windowSize = 25, double k = 0.18, double r = 128.0);
    static std::vector<QuestionBox> detectCandidateBoxes(const unsigned char* binData, int width, int height);
};
#endif

@interface GSImageProcessor : NSObject

/// 缩放并增强图片以便于 OCR 识别 (限制长边 <= 1400，自适应对比度)
+ (UIImage *)preprocessForOcr:(UIImage *)image maxDimension:(CGFloat)maxDim;

/// 将 UIImage 转换为高质量 Base64 字符串
+ (NSString *)base64StringFromImage:(UIImage *)image compressionQuality:(CGFloat)quality;

/// 自动分析试卷并检测所有题目的矩形选框 (返回归一化 CGRect 包装为 NSValue)
+ (NSArray<NSValue *> *)detectQuestionBoxesInImage:(UIImage *)image;

/// 根据归一化坐标裁剪高精子图
+ (UIImage *)cropImage:(UIImage *)image normalizedRect:(CGRect)normRect;

@end

#endif /* ImageProcessor_hpp */
