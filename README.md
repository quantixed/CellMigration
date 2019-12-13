# CellMigration

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.3574118.svg)](https://doi.org/10.5281/zenodo.3574118)

This is a set of functions to load particle tracks and analyse 2D cell migration in Igor.

[**Examples**](#Examples) | [**Workflow**](#Workflow) | [**Superplots**](#Superplots)

## Examples

Summary layout showing comparison of two experimental treatments.

![img](img/summaryLayout.png?raw=true "image")

This compares:

* Cumulative distance over time
* Instantaneous speed over time, histogram of velocities
* Directionality ratio (d/D) over time
* Mean squared displacement
* Direction autocorrelation
* Cell turning
* Average speed
* Fastest segment time (Strava for cells!)

A individual report is also generated for each experimental condition. These reports show how all the cells behaved. In addition to the measures described above, there are x ways to visualise individual cell tracks:

* Tracks of all cells overlaid
* Tracks of all cells shown as a heatmap
* A bootstrapped + rotated view of cell tracks to visualise the average explored space by the cells
* An _image quilt_ of a sample of cell tracks arrayed on a grid. The number and duration of tracks is optimised for comparison between experimental condition.
* _Sparkline image_ which shows a diagonal sample through the image quilt rotated so that the end point of the track is vertically above the start. This helps to visualise directionality.

![img](img/Ctrl_layout.png?raw=true "image")

![img](img/Ctrl_layout2.png?raw=true "image")


## Workflow

1. Cells are tracked manually in ImageJ/FIJI using [Manual Tracking](http://rsbweb.nih.gov/ij/plugins/track/track.html).
2. Save the outputs as csv, or copy-paste them into an Excel workbook*.
3. Save a copy of `CellMigration.ipf` in *Wavemetrics/Igor Pro 8 User Files/User Procedures*. Open in Igor and compile.
4. Run using CellMigr>Cell Migration...

The dialog asks the user how many conditions are to be loaded and analysed. At this point, please confirm the time step and pixel size of the movies.

![img](img/ss_specify.png?raw=true "image")

Next, a panel pops up where the user specifies:

1. The name of each condition
2. Either the directory containing all the csvs from that condition *or* the Excel workbook containing the data
3. OPTIONALLY, data containing offset information (if stage travel is an issue in the experiments). Again, either as a directory of CSVs or an Excel workbook.

![img](img/ss_filepicker.png?raw=true "image")

The number of rows is determined by the previous dialog.

Now click **Do it** and Igor will do the rest!

Reports are made for each condition and also a summary layout comparing all conditions. Select Macros>Save Reports to save all reports as PDF (Mac) or EMF (Windows).

Everything can be recolored by manually editing `root:colorwave` and running the command from the CellMigr menu.

### Excel formatting

NOTE: no headers in Excel file. Keep data to columns A-H, max of 2000 rows.

* A - 0 - ImageJ row
* B - 1 - Track No
* C - 2 - Slice No
* D - 3 - x (in px)
* E - 4 - y (in px)
* F - 5 - distance
* G - 6 - velocity (speed)
* H - 7 - pixel value

### Colour palettes
Colours are taken from Paul Tol SRON stylesheet. A maximum of 12 conditions are handled properly, with >12 conditions having non-unique colours. By editing the 3-column colorWave (root:colorWave) it is possible to recolor all the plots by subsequently clicking Macros > Recolor Everything.

![img](img/colorPlot.png?raw=true "image")

## Superplots
The main cell migration program is useful for analysing single experiment data or data aggregated from multiple experiments. However, the experimental reproducibibility is useful to examine and this can be done using the Superplot program.

If you have two conditions and four experimental repeats (eight datasets in total). You can analyse in a few different ways:

- Superplot - respects the experimental repeats and allows comparison of reproducibility. Aggregates data by condition like _CellMigration_ does.
- CellMigration - analyse the data as an eight-way comparison, or collapse the data before loading for a two-way comparison.

Select CellMigr>Superplot... and specify the number of conditions and experimental repeats (unequal numbers of repeats across conditions are not supported).

![img](img/sp_specify.png?raw=true "image")

Next, a panel pops up where the user specifies:

1. The name of each condition (entries are autofilled for the condition)
2. Either the directory containing all the csvs from that condition-repeat *or* the Excel workbook containing the data (offsetting data is optional).

![img](img/sp_filepicker.png?raw=true "image")

The analysis proceeds as described for the main program, giving aggregated reports as before. However, two superplots are generated for the cell migration speed data. A t-test or Dunnett post-hoc test (control is first group) is done on the experimental repeats.

![img](img/superplot.png?raw=true "image")

The colours in the right hand superplot correspond to experimental repeat.

### Compatability
Written for IgorPro 8.

- From v 1.12 there was no back-compatability for IgorPro 7.
- From v 1.03 there was no back-compatability for IgorPro 6.37.

### Notes
\* *CSV output:* This is the preferred method. Save the output direct from ImageJ. Use a directory of CSVs per condition. They can be named anything, as long as they have .csv extension. If you need offsetting then the same named files are needed for this (in a different directory).

\*  *Excel:* Use 1 workbook per condition. Suggest that each sheet is a field of view, containing all cells in the field. So for two experimental conditions with 10 multipoints each, you will have two workbooks each with 10 worksheets.

\* *Superplots:* To analyse conditions, but take into account experimental replications, use the superplot functionality. Here, one directory of CSVs (or Excel workbook) is required for each condition-replication. So for two conditions, with four replications, eight directories/workbooks are required.

\*  *Offsetting:* For offsetting data, a directory of CSVs or workbook per condition is needed with corresponding files or sheets to the primary data. It is important that every frame has a tracked point.