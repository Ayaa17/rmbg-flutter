#import <Foundation/Foundation.h>
#import <tensorflow/c/c_api.h>

@interface TensorFlowModel : NSObject

- (instancetype)initWithModelPath:(NSString *)modelPath;
- (int)runInference:(float *)data length:(int)data_length;

@end

@implementation TensorFlowModel {
    TF_Graph* _graph;
    TF_Session* _session;
    TF_Status* _status;
}

void NoOpDeallocator(void *data, size_t a, void *b) {}

void FreeBuffer(void* data, size_t length) {
    free(data);
}

- (instancetype)initWithModelPath:(NSString *)modelPath {
    self = [super init];
    if (self) {
        _status = TF_NewStatus();
        _graph = TF_NewGraph();

        TF_SessionOptions* options = TF_NewSessionOptions();
        _session = TF_NewSession(_graph, options, _status);
        TF_DeleteSessionOptions(options);

        const char* model_path = [modelPath UTF8String];
        TF_Buffer* buffer = ReadFile(model_path);
        if (buffer == NULL) {
            NSLog(@"Failed to read model file");
            return nil;
        }

        TF_ImportGraphDefOptions* import_opts = TF_NewImportGraphDefOptions();
        TF_GraphImportGraphDef(_graph, buffer, import_opts, _status);
        TF_DeleteImportGraphDefOptions(import_opts);
        TF_DeleteBuffer(buffer);

        if (TF_GetCode(_status) != TF_OK) {
            NSLog(@"Failed to import graph: %s", TF_Message(_status));
            return nil;
        }
    }
    return self;
}

- (int)runInference:(float *)data length:(int)data_length {
    int maxIndex = -1;

    const int NumInputs = 1;
    const int NumOutputs = 1;
    const char *INPUT_OPER_NAME = "serving_default_input";
    const char *OUTPUT_OPER_NAME = "PartitionedCall";
    const int INPUT_SIZE = 224;
    const int PIXEL_SIZE = 3;
    const int OUTPUT_SIZE = 45;

    TF_Output t_input = {TF_GraphOperationByName(_graph, INPUT_OPER_NAME), 0};
    TF_Output t_output = {TF_GraphOperationByName(_graph, OUTPUT_OPER_NAME), 0};

    if (t_input.oper != nullptr && t_output.oper != nullptr) {
        TF_Output Input[NumInputs] = {t_input};
        TF_Output Output[NumOutputs] = {t_output};
        TF_Tensor *InputValues[NumInputs];
        TF_Tensor *OutputValues[NumOutputs];

        int64_t dims[] = {1, INPUT_SIZE, INPUT_SIZE, PIXEL_SIZE};
        size_t ndata = sizeof(float) * data_length;
        TF_Tensor *int_tensor = TF_NewTensor(TF_FLOAT, dims, 4, data, ndata, &NoOpDeallocator, nullptr);

        if (int_tensor != nullptr) {
            InputValues[0] = int_tensor;
            TF_SessionRun(_session, nullptr, Input, InputValues, NumInputs, Output, OutputValues, NumOutputs, nullptr, 0, nullptr, _status);

            if (TF_GetCode(_status) == TF_OK) {
                void *buff = TF_TensorData(OutputValues[0]);
                float *offsets = static_cast<float *>(buff);
                maxIndex = 0;
                double maxValue = offsets[0];
                for (int i = 1; i < OUTPUT_SIZE; i++) {
                    auto value = offsets[i];
                    if (maxValue >= value) continue;
                    maxValue = value;
                    maxIndex = i;
                }
            }
        }
        TF_DeleteTensor(int_tensor);
    }
    return maxIndex;
}

- (void)dealloc {
    TF_DeleteSession(_session, _status);
    TF_DeleteGraph(_graph);
    TF_DeleteStatus(_status);
}

TF_Buffer* ReadFile(const char* file) {
    FILE *f = fopen(file, "rb");
    if (f == NULL) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    void* data = malloc(fsize);
    fread(data, fsize, 1, f);
    fclose(f);

    TF_Buffer* buffer = TF_NewBuffer();
    buffer->data = data;
    buffer->length = fsize;
    buffer->data_deallocator = FreeBuffer;
    return buffer;
}

@end
