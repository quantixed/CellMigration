# CellMigration
Analysis of 2D cell migration in Igor Pro

This is a set of functions to load particle tracks and analyse 2D cell migration in Igor.

Workflow
--------

1. Cells are tracked manually in ImageJ/FIJI using [Manual Tracking](http://rsbweb.nih.gov/ij/plugins/track/track.html).
2. Save the outputs as csv, or copy-paste them into an Excel Workbook*.
3. Save a copy of `CellMigration.ipf` in *Wavemetrics/Igor Pro 7 User Files/User Procedures*. Open in Igor and compile.
4. Run using Macros>Cell Migration...

The dialog asks the user how many conditions are to be loaded and analysed. At this point, please confirm the time step and pixelsize of the movies.<br />
Next, a panel pops up where the user specifies:

1. the name of each condition
2. Either the directory containing all the csvs from that condition *or* the Excel workbook containing the data
3. OPTIONALLY, data containing offset information (if stage travel is an issue in the experiments). Again, either as a directory of CSVs or an Excel workbook.<br />

Now click **Do it** and Igor will do the rest!

It will calculate and display the following:

* Cumulative distance over time
* Instantaneous speed over time, histogram of velocities
* Tracks of all cells for visualisation
* Directionality ratio (d/D) over time
* Mean squared displacement
* Direction autocorrelation

Reports are made for each condition and also a summary layout comparing all conditions.

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
Colours are taken from Paul Tol SRON stylesheet. A maximum of 12 conditions are handled properly, with >12 conditions having non-unique colours.

### Compatability
Written for IgorPro 7. From v 1.03 there is no back-compatability for IgorPro 6.37.

### Notes
\* *CSV output:* This is the preferred method. Save the output direct from ImageJ. Use a directory of CSVs percondition. They can be named anything, as long as they have .csv extension. If you need offsetting then the same named files are needed for this (in a different directory).

\*  *Excel:* Use 1 workbook per condition. Suggest that each sheet is a field of view, containing all cells in the field. So for two experimental conditions with 10 multipoints each, you will have two workbooks each with 10 worksheets.

\*  *Offsetting:* For offsetting data, a workbook per condition is needed with corresponding sheets to the primary data. It is important that every frame has a tracked point.

\* For experiments where a manipulation is done partway through the experiment (e.g. adding a drug). Suggest that pre and post conditions are kept in separate workbooks. Analyzing them will give statistics for each condition (pre and post). If you'd like to stitch the tracks together to analyze data per cell, as long as the tracks are named consistently and the conditions feature *pre* and *post*, you can use `MigrationAuxProcs.ipf` to do this. Execute `StitchIV()` to generate a report of this type.