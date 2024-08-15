#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <iostream>
#include <string>

#include "flutter_window.h"
#include "utils.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "tensorflow/c/c_api.h"

void NoOpDeallocator(void *data, size_t a, void *b) {}

float* recognizeImageGame(float* data, int data_length) {

    const int NumInputs = 1;
    const int NumOutputs = 1;

    const char *TAGS = "serve";
    const int NUM_TAGS = 1;
    const char *INPUT_OPER_NAME = "serving_default_input_1";
    const char *OUTPUT_OPER_NAME = "StatefulPartitionedCall";
    const int INPUT_SIZE = 512;
    const int PIXEL_SIZE = 3;

    TF_Graph *Graph = TF_NewGraph();
    TF_Status *Status = TF_NewStatus();
    TF_SessionOptions *SessionOpts = TF_NewSessionOptions();

    float* result = new float[INPUT_SIZE * INPUT_SIZE]();

    if (TF_GetCode(Status) == TF_OK) {
        TF_Buffer *RunOpts = nullptr;
        const char *saved_model_dir = "windows/runner/model-bgrm/";
        // const char *saved_model_dir = "data/flutter_assets/assets/model-bgrm/";

        TF_Session *Session = TF_LoadSessionFromSavedModel(SessionOpts, RunOpts, saved_model_dir, &TAGS, NUM_TAGS, Graph, nullptr, Status);

        if (TF_GetCode(Status) == TF_OK) {
            TF_Output t_input = {TF_GraphOperationByName(Graph, INPUT_OPER_NAME), 0};
            TF_Output t_output = {TF_GraphOperationByName(Graph, OUTPUT_OPER_NAME), 0};

            if (t_input.oper != nullptr && t_output.oper != nullptr) {
                TF_Output Input[NumInputs] = {t_input};
                TF_Output Output[NumOutputs] = {t_output};
                TF_Tensor *InputValues[NumInputs];
                TF_Tensor *OutputValues[NumOutputs];

                int64_t dims[] = {NumInputs, INPUT_SIZE, INPUT_SIZE, PIXEL_SIZE};
                size_t ndata = sizeof(float) * data_length;
                TF_Tensor *int_tensor = TF_NewTensor(TF_FLOAT, dims, 4, data, ndata, &NoOpDeallocator, nullptr);

                if (int_tensor != nullptr) {
                    InputValues[0] = int_tensor;
                    TF_SessionRun(Session, nullptr, Input, InputValues, NumInputs, Output, OutputValues, NumOutputs, nullptr, 0, nullptr, Status);

                    if (TF_GetCode(Status) == TF_OK) {
                        void *buff = TF_TensorData(OutputValues[0]);
                        std::memcpy(result, buff, sizeof(float) * INPUT_SIZE * INPUT_SIZE);
                    }
                }
                TF_DeleteTensor(int_tensor);
            }
            TF_CloseSession(Session, Status);
        }
        TF_DeleteSession(Session, Status);
    }
    TF_DeleteSessionOptions(SessionOpts);
    TF_DeleteStatus(Status);
    TF_DeleteGraph(Graph);

    return result;
}

void RegisterGameDetectMethodChannel(flutter::FlutterViewController *controller) {
    auto channel = std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
            controller->engine()->messenger(), "com.example.hello_flutter/game_detect",
                    &flutter::StandardMethodCodec::GetInstance());

    channel->SetMethodCallHandler(
            [](const flutter::MethodCall<flutter::EncodableValue> &call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
                if (call.method_name().compare("game_detect") != 0) {
                    result->NotImplemented();
                    return;
                }

                if (const auto *arguments = std::get_if<flutter::EncodableMap>(call.arguments())) {
                    auto it = arguments->find(flutter::EncodableValue("image"));
                    if (it == arguments->end()) {
                        result->Error("Bad Arguments", "Expected image data");
                        return;
                    }

                    const auto& image_data = it->second;
                    if (const auto* float_list = std::get_if<std::vector<float>>(&image_data)) {
                        std::vector<float> image_vector = *float_list;

                        if (image_vector.size() > static_cast<size_t>(std::numeric_limits<int>::max())) {
                            throw std::overflow_error("size of image_vector over max int");
                        }

                        float* index = recognizeImageGame(image_vector.data(), static_cast<int>(image_vector.size()));
                        std::vector<float> floatVector(index, index + 262144);
                        result->Success(flutter::EncodableValue(floatVector));

                    } else {
                        result->Error("Bad Arguments", "Expected image data in Float32List format");
                    }
                } else {
                    result->Error("Bad Arguments", "Expected image data");
                }
            });
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
        CreateAndAttachConsole();
    }

    ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    flutter::DartProject project(L"data");

    std::vector<std::string> command_line_arguments = GetCommandLineArguments();

    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(L"Remove Portrait Background", origin, size)) {
        return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);

    RegisterGameDetectMethodChannel(window.GetController());

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
        ::TranslateMessage(&msg);
        ::DispatchMessage(&msg);
    }

    ::CoUninitialize();
    return EXIT_SUCCESS;
}
