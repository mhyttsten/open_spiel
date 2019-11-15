
# GridMaze Environment

One of the first problems you solve when studying reinforcement learning is to solve mazes. 
It is often formulated as 

![ExampleImage]("images/GridMazeExample.png")


## Building

To use Swift OpenSpiel, download a recent Swift for TensorFlow toolchain following these
[installation instructions](https://github.com/tensorflow/swift/blob/master/Installation.md)
(available for macOS and Ubuntu currently). Swift OpenSpiel currently builds
with the latest stable toolchains.

Using the toolchain, build and test Swift OpenSpiel like a normal SwiftPM package:

```bash
cd swift
swift build # Build the OpenSpiel library.
swift test  # Run tests.
```

## Join the community!

If you have any questions about Swift for TensorFlow (or would like to share
your work or research with the community), please join our mailing list
[`swift@tensorflow.org`](https://groups.google.com/a/tensorflow.org/forum/#!forum/swift).
