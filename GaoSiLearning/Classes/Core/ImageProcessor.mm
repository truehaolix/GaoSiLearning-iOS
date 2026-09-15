#import "ImageProcessor.hpp"
#include <cmath>
#include <algorithm>
#include <vector>

#ifdef __cplusplus
void ImageProcessorCore::enhanceContrastGrayscale(unsigned char* grayData, int width, int height) {
    int totalPixels = width * height;
    if (totalPixels <= 0 || !grayData) return;

    // 统计灰度直方图
    int hist[256] = {0};
    for (int i = 0; i < totalPixels; ++i) {
        hist[grayData[i]]++;
    }

    // 计算分位数截断 (1% 阴影, 99% 高光)
    int lowCount = totalPixels * 0.01;
    int highCount = totalPixels * 0.99;
    int acc = 0;
    int minVal = 0, maxVal = 255;

    for (int i = 0; i < 256; ++i) {
        acc += hist[i];
        if (acc >= lowCount) {
            minVal = i;
            break;
        }
    }
    acc = 0;
    for (int i = 0; i < 256; ++i) {
        acc += hist[i];
        if (acc >= highCount) {
            maxVal = i;
            break;
        }
    }

    if (maxVal <= minVal) maxVal = minVal + 1;

    // 线性拉伸映射
    for (int i = 0; i < totalPixels; ++i) {
        int v = grayData[i];
        if (v < minVal) v = 0;
        else if (v > maxVal) v = 255;
        else v = (int)((v - minVal) * 255.0 / (maxVal - minVal));
        grayData[i] = (unsigned char)v;
    }
}

void ImageProcessorCore::sauvolaBinarize(const unsigned char* grayData, unsigned char* outputBin, int width, int height, int windowSize, double k, double r) {
    int wh = width * height;
    if (wh <= 0) return;

    // 构建积分图 (Integral Image) 与二阶积分图 (Integral Sq Image)
    std::vector<double> integral(wh, 0.0);
    std::vector<double> integralSq(wh, 0.0);

    for (int y = 0; y < height; ++y) {
        double rowSum = 0.0;
        double rowSumSq = 0.0;
        for (int x = 0; x < width; ++x) {
            int idx = y * width + x;
            double val = grayData[idx];
            rowSum += val;
            rowSumSq += val * val;
            if (y == 0) {
                integral[idx] = rowSum;
                integralSq[idx] = rowSumSq;
            } else {
                integral[idx] = integral[idx - width] + rowSum;
                integralSq[idx] = integralSq[idx - width] + rowSumSq;
            }
        }
    }

    int halfW = windowSize / 2;
    for (int y = 0; y < height; ++y) {
        int y1 = std::max(0, y - halfW);
        int y2 = std::min(height - 1, y + halfW);
        for (int x = 0; x < width; ++x) {
            int x1 = std::max(0, x - halfW);
            int x2 = std::min(width - 1, x + halfW);
            int count = (x2 - x1 + 1) * (y2 - y1 + 1);

            double A = (x1 > 0 && y1 > 0) ? integral[(y1 - 1) * width + (x1 - 1)] : 0;
            double B = (y1 > 0) ? integral[(y1 - 1) * width + x2] : 0;
            double C = (x1 > 0) ? integral[y2 * width + (x1 - 1)] : 0;
            double D = integral[y2 * width + x2];
            double sum = D - B - C + A;

            double ASq = (x1 > 0 && y1 > 0) ? integralSq[(y1 - 1) * width + (x1 - 1)] : 0;
            double BSq = (y1 > 0) ? integralSq[(y1 - 1) * width + x2] : 0;
            double CSq = (x1 > 0) ? integralSq[y2 * width + (x1 - 1)] : 0;
            double DSq = integralSq[y2 * width + x2];
            double sumSq = DSq - BSq - CSq + ASq;

            double mean = sum / count;
            double variance = (sumSq - (sum * sum) / count) / count;
            double stdDev = (variance > 0) ? std::sqrt(variance) : 0;

            // Sauvola 阈值: T = m * (1 + k * (s / r - 1))
            double thresh = mean * (1.0 + k * (stdDev / r - 1.0));
            int idx = y * width + x;
            outputBin[idx] = (grayData[idx] <= thresh) ? 0 : 255; // 0 为前景(笔划黑)，255 为背景白
        }
    }
}

std::vector<QuestionBox> ImageProcessorCore::detectCandidateBoxes(const unsigned char* binData, int width, int height) {
    std::vector<QuestionBox> boxes;
    if (width <= 0 || height <= 0 || !binData) return boxes;

    // 按行投影 (水平方向黑像素密度)
    std::vector<int> rowDensity(height, 0);
    for (int y = 0; y < height; ++y) {
        int cnt = 0;
        for (int x = 0; x < width; ++x) {
            if (binData[y * width + x] == 0) { // 前景墨迹
                cnt++;
            }
        }
        rowDensity[y] = cnt;
    }

    // 寻找空白行分割题块
    int minSpacing = (int)(height * 0.015);
    int minBoxHeight = (int)(height * 0.04);
    int inQuestion = 0;
    int startY = 0;
    int blankCount = 0;

    for (int y = 0; y < height; ++y) {
        if (rowDensity[y] > width * 0.01) { // 有字符行
            if (!inQuestion) {
                inQuestion = 1;
                startY = y;
            }
            blankCount = 0;
        } else { // 空白分割行
            if (inQuestion) {
                blankCount++;
                if (blankCount >= minSpacing || y == height - 1) {
                    int endY = y - blankCount;
                    if (endY - startY >= minBoxHeight) {
                        // 寻找选区内的左右有效边界
                        int leftX = 0;
                        int rightX = width - 1;
                        for (int x = 0; x < width; ++x) {
                            int hasPixel = 0;
                            for (int sy = startY; sy <= endY; ++sy) {
                                if (binData[sy * width + x] == 0) {
                                    hasPixel = 1;
                                    break;
                                }
                            }
                            if (hasPixel) {
                                leftX = std::max(0, x - (int)(width * 0.02));
                                break;
                            }
                        }
                        for (int x = width - 1; x >= 0; --x) {
                            int hasPixel = 0;
                            for (int sy = startY; sy <= endY; ++sy) {
                                if (binData[sy * width + x] == 0) {
                                    hasPixel = 1;
                                    break;
                                }
                            }
                            if (hasPixel) {
                                rightX = std::min(width - 1, x + (int)(width * 0.02));
                                break;
                            }
                        }

                        QuestionBox qb;
                        qb.rect = CGRectMake((CGFloat)leftX / width,
                                             (CGFloat)startY / height,
                                             (CGFloat)(rightX - leftX) / width,
                                             (CGFloat)(endY - startY) / height);
                        qb.confidence = 0.95f;
                        qb.index = (int)boxes.size() + 1;
                        boxes.push_back(qb);
                    }
                    inQuestion = 0;
                    blankCount = 0;
                }
            }
        }
    }

    // 若未检测到有效区域，默认生成居中题框
    if (boxes.empty()) {
        QuestionBox qb;
        qb.rect = CGRectMake(0.05, 0.1, 0.9, 0.35);
        qb.confidence = 0.8f;
        qb.index = 1;
        boxes.push_back(qb);
    }

    return boxes;
}
#endif

@implementation GSImageProcessor

+ (UIImage *)preprocessForOcr:(UIImage *)image maxDimension:(CGFloat)maxDim {
    if (!image) return nil;

    CGSize origSize = image.size;
    CGFloat width = origSize.width;
    CGFloat height = origSize.height;

    CGFloat scale = 1.0;
    if (width > maxDim || height > maxDim) {
        scale = (width > height) ? (maxDim / width) : (maxDim / height);
    }
    CGSize targetSize = CGSizeMake(floor(width * scale), floor(height * scale));

    // 重绘为灰度并执行局部对比度增强
    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef cgImage = scaledImage.CGImage;
    size_t w = CGImageGetWidth(cgImage);
    size_t h = CGImageGetHeight(cgImage);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    std::vector<unsigned char> grayBuffer(w * h);
    CGContextRef context = CGBitmapContextCreate(grayBuffer.data(), w, h, 8, w, colorSpace, kCGImageAlphaNone);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    // C++ 对比度拉伸
    ImageProcessorCore::enhanceContrastGrayscale(grayBuffer.data(), (int)w, (int)h);

    CGColorSpaceRef outColorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef outContext = CGBitmapContextCreate(grayBuffer.data(), w, h, 8, w, outColorSpace, kCGImageAlphaNone);
    CGImageRef enhancedCgImage = CGBitmapContextCreateImage(outContext);
    CGContextRelease(outContext);
    CGColorSpaceRelease(outColorSpace);

    UIImage *result = [UIImage imageWithCGImage:enhancedCgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(enhancedCgImage);

    return result ?: image;
}

+ (NSString *)base64StringFromImage:(UIImage *)image compressionQuality:(CGFloat)quality {
    if (!image) return @"";
    NSData *data = UIImageJPEGRepresentation(image, quality);
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

+ (NSArray<NSValue *> *)detectQuestionBoxesInImage:(UIImage *)image {
    if (!image) return @[];

    // 缩放到分析尺寸提高响应速度
    CGFloat maxAnalysisDim = 1000.0;
    CGSize origSize = image.size;
    CGFloat scale = 1.0;
    if (origSize.width > maxAnalysisDim || origSize.height > maxAnalysisDim) {
        scale = (origSize.width > origSize.height) ? (maxAnalysisDim / origSize.width) : (maxAnalysisDim / origSize.height);
    }
    int w = (int)floor(origSize.width * scale);
    int h = (int)floor(origSize.height * scale);

    std::vector<unsigned char> grayBuffer(w * h);
    std::vector<unsigned char> binBuffer(w * h);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(grayBuffer.data(), w, h, 8, w, colorSpace, kCGImageAlphaNone);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    ImageProcessorCore::sauvolaBinarize(grayBuffer.data(), binBuffer.data(), w, h, 25, 0.18, 128.0);
    std::vector<QuestionBox> boxes = ImageProcessorCore::detectCandidateBoxes(binBuffer.data(), w, h);

    NSMutableArray<NSValue *> *result = [NSMutableArray array];
    for (const auto& b : boxes) {
        [result addObject:[NSValue valueWithCGRect:b.rect]];
    }
    return [result copy];
}

+ (UIImage *)cropImage:(UIImage *)image normalizedRect:(CGRect)normRect {
    if (!image) return nil;

    CGImageRef cgImage = image.CGImage;
    CGFloat width = CGImageGetWidth(cgImage);
    CGFloat height = CGImageGetHeight(cgImage);

    CGRect pixelRect = CGRectMake(normRect.origin.x * width,
                                  normRect.origin.y * height,
                                  normRect.size.width * width,
                                  normRect.size.height * height);

    // 裁剪与防越界截断
    pixelRect = CGRectIntersection(pixelRect, CGRectMake(0, 0, width, height));
    if (CGRectIsNull(pixelRect) || pixelRect.size.width <= 0 || pixelRect.size.height <= 0) {
        return image;
    }

    CGImageRef croppedCg = CGImageCreateWithImageInRect(cgImage, pixelRect);
    UIImage *cropped = [UIImage imageWithCGImage:croppedCg scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(croppedCg);
    return cropped;
}

@end
