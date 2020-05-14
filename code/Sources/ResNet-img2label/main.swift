// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Datasets
import ImageClassificationModels
import TensorFlow
import ModelSupport

let batchSize = 10

let dsURL = URL(fileURLWithPath: "/notebooks/language2motion.gt/data/img2label_ds_v2", isDirectory: true)

let dataset = Img2Label(batchSize: batchSize, dsURL: dsURL, normalizing: true)
print("dataset.training.count: \(dataset.training.count)")
print("dataset.test.count: \(dataset.test.count)")

// let device = Device.defaultXLA

// Use the network sized for img2label
var model: ResNet = ResNet(classCount: dataset.labels.count, depth: .resNet18, downsamplingInFirstStage: false)
// model = model.move(to: device)

// the classic ImageNet optimizer setting diverges on CIFAR-10
// let optimizer = SGD(for: model, learningRate: 0.1, momentum: 0.9)
var optimizer = SGD(for: model, learningRate: 0.001, momentum: 0.9)
// optimizer = SGD(copying: optimizer, to: device)

print("Starting img2label training...")

time() {
    for epoch in 1...10 {
        // print("epoch \(epoch)")
        Context.local.learningPhase = .training
        var trainingLossSum: Float = 0
        var trainingBatchCount = 0
        for batch in dataset.training.sequenced() {
            // print("progress \(100.0*Float(trainingBatchCount)/Float(dataset.training.count))%")
            let (images, labels) = (batch.first, batch.second)
            // let (eagerImages, eagerLabels) = (batch.first, batch.second)
            // let images = Tensor(copying: eagerImages, to: device)
            // let labels = Tensor(copying: eagerLabels, to: device)

            let (loss, gradients) = valueWithGradient(at: model) { model -> Tensor<Float> in
                let logits = model(images)
                return softmaxCrossEntropy(logits: logits, labels: labels)
            }
            trainingLossSum += loss.scalarized()
            trainingBatchCount += 1
            optimizer.update(&model, along: gradients)
            // LazyTensorBarrier()
        }

        Context.local.learningPhase = .inference
        var testLossSum: Float = 0
        var testBatchCount = 0
        var correctGuessCount = 0
        var totalGuessCount = 0
        for batch in dataset.test.sequenced() {
            // print("batch")
            let (images, labels) = (batch.first, batch.second)
            // let (eagerImages, eagerLabels) = (batch.first, batch.second)
            // let images = Tensor(copying: eagerImages, to: device)
            // let labels = Tensor(copying: eagerLabels, to: device)
            let logits = model(images)
            testLossSum += softmaxCrossEntropy(logits: logits, labels: labels).scalarized()
            // LazyTensorBarrier()
            testBatchCount += 1

            let correctPredictions = logits.argmax(squeezingAxis: 1) .== labels
            correctGuessCount = correctGuessCount
                + Int(
                    Tensor<Int32>(correctPredictions).sum().scalarized())
            totalGuessCount = totalGuessCount + batchSize
        }

        let accuracy = Float(correctGuessCount) / Float(totalGuessCount)
        print(
            """
            [Epoch \(epoch)] \
            Accuracy: \(correctGuessCount)/\(totalGuessCount) (\(accuracy)) \
            Loss: \(testLossSum / Float(testBatchCount))
            """
        )
    }
}
