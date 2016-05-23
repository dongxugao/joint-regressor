#!/usr/bin/env python3

from argparse import ArgumentParser
from itertools import cycle
from os import path
from sys import exit, stderr

import matplotlib
from matplotlib import pyplot as plt
from matplotlib.ticker import AutoMinorLocator
from pandas import read_csv

THRESH = 'Threshold'
MARKERS = [None]
# List of matplotlib.artist.Artist properties which we should copy between
# subplots
COMMON_PROPS = {
    'linestyle', 'marker', 'visible', 'drawstyle', 'linewidth',
    'markeredgewidth', 'markeredgecolor', 'markerfacecoloralt',
    'dash_joinstyle', 'zorder', 'markersize', 'solid_capstyle',
    'dash_capstyle', 'markevery', 'fillstyle', 'markerfacecolor', 'label',
    'alpha', 'path_effects', 'color', 'solid_joinstyle'
}
PRIORITIES = {
    'Shoulder': 0,
    'Elbow': 1,
    'Wrist': 2
}

parser = ArgumentParser(
    description="Take accuracy at different thresholds and plot it nicely"
)
parser.add_argument(
    '--save', metavar='PATH', type=str, default=None,
    help="Destination file for graph"
)
parser.add_argument(
    '--input', nargs=2, metavar=('NAME', 'PATH'), action='append', default=[],
    help='Name (title) and path of CSV to plot; can be specified repeatedly'
)
parser.add_argument(
    '--poster', action='store_true', dest='is_poster', default=False,
    help='Produce a plot for the poster rather than the report.'
)
parser.add_argument(
    '--xmax', type=float, default=None, help='Maximum value along the x-axis'
)
parser.add_argument(
    '--dims', nargs=2, type=float, metavar=('WIDTH', 'HEIGHT'),
    default=[6, 3], help="Dimensions (in inches) for saved plot"
)


def load_data(inputs):
    labels = []
    thresholds = None
    parts = None

    for name, path in inputs:
        labels.append(name)

        csv = read_csv(path)

        if thresholds is None:
            thresholds = csv[THRESH]
        if parts is None:
            parts = {part: [] for part in csv.columns.difference([THRESH])}

        assert len(parts) == len(csv.columns.difference([THRESH]))
        assert (csv[THRESH] == thresholds).all()

        for part in parts:
            part_vals = csv[part]
            assert len(part_vals) == len(thresholds)
            parts[part].append(part_vals)

    return labels, thresholds, parts

if __name__ == '__main__':
    args = parser.parse_args()
    if not args.input:
        parser.print_usage(stderr)
        print('error: must specify at least one --input', file=stderr)
        exit(1)

    if args.is_poster:
        matplotlib.rcParams.update({
            'font.family': 'Ubuntu',
            'pgf.rcfonts': False,
            'xtick.labelsize': '12',
            'ytick.labelsize': '12',
            'legend.fontsize': '14',
            'axes.labelsize': '16',
            'axes.titlesize': '18',
        })
    else:
        matplotlib.rcParams.update({
            'font.family': 'serif',
            'pgf.rcfonts': False,
            'pgf.texsystem': 'pdflatex',
            'xtick.labelsize': 'xx-small',
            'ytick.labelsize': 'xx-small',
            'legend.fontsize': 'xx-small',
            'axes.labelsize': 'x-small',
            'axes.titlesize': 'small',
        })

    labels, thresholds, parts = load_data(args.input)

    _, subplots = plt.subplots(1, len(parts), sharey=True)
    common_handles = None
    part_keys = sorted(parts.keys(), key=lambda s: PRIORITIES.get(s, -1))
    for part_name, subplot in zip(part_keys, subplots):
        pcks = parts[part_name]
        if common_handles is None:
            # Record first lot of handles for reuse
            common_handles = []
            for pck, label, marker in zip(pcks, labels, cycle(MARKERS)):
                handle, = subplot.plot(
                    thresholds, 100 * pck, label=label, marker=marker
                )
                common_handles.append(handle)
        else:
            for pck, handle in zip(pcks, common_handles):
                props = handle.properties()
                kwargs = {k: v for k, v in props.items() if k in COMMON_PROPS}
                subplot.plot(thresholds, 100 * pck, **kwargs)

        # Labels, titles
        subplot.set_title(part_name)
        subplot.set_xlabel('Threshold (px)')
        subplot.grid(which='both')

        if args.xmax is not None:
            subplot.set_xlim(xmax=args.xmax)

    subplots[0].set_ylabel('Accuracy (%)')
    subplots[0].set_ylim(ymin=0, ymax=100)
    minor_locator = AutoMinorLocator(2)
    subplots[0].yaxis.set_minor_locator(minor_locator)
    subplots[0].set_yticks(range(0, 101, 20))
    ax = plt.gca()
    box = ax.get_position()
    ax.set_position([box.x0, box.y0, box.width * 0.8, box.height])
    legend = plt.figlegend(
        common_handles, labels, 'center left', bbox_to_anchor=(0.965, 0.5),
        borderaxespad=0.
    )

    if args.save is None:
        plt.show()
    else:
        print('Saving figure to', args.save)
        plt.gcf().set_size_inches(args.dims)
        plt.tight_layout()
        plt.savefig(
            args.save, bbox_inches='tight', bbox_extra_artists=[legend],
            transparent=True
        )
