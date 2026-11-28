import sys
import time
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def main(ext="png", n="256"):
    n = int(n)
    x = np.linspace(-3.0, 3.0, n)
    y = np.linspace(-3.0, 3.0, n)
    X, Y = np.meshgrid(x, y)
    Z = np.sin(X) * np.cos(Y) * np.exp(-0.1 * (X**2 + Y**2))
    plt.contourf(X, Y, Z, cmap="viridis")
    plt.colorbar()
    plt.title("contourf benchmark")
    plt.savefig("contourf_py." + ext)


if __name__ == "__main__":
    t0 = time.perf_counter()
    main(*sys.argv[1:3])
    print(f"RUN_SECONDS {time.perf_counter() - t0:.6f}")
