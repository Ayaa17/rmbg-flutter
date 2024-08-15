#import <Foundation/Foundation.h>

@interface TensorFlowModel : NSObject

- (instancetype)initWithModelPath:(NSString *)modelPath;
- (int)runInference:(float *)data length:(int)data_length;

@end