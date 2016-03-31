# CellMigration
Analysis of 2D cell migration in Igor Pro

This is a set of functions to load particle tracks and analyse 2D cell migration in Igor.

Workflow
--------

1. Cells are tracked manually in ImageJ/FIJI using [Manual Tracking](http://rsbweb.nih.gov/ij/plugins/track/track.html).
2. Organise the outputs in an Excel Workbook, 1 workbook per condition*.
3. Save a copy of LoadMigration.ipf in your *User Procedures* folder. Open in Igor and compile.
4. Go to Macros>Cell Migration... or Execute <code>Migrate()</code> in the Command Window <code>cmd + j</code>.

The dialog asks the user how many conditions (workbooks) are to be loaded and analysed.<br />
The user is then asked to name the condition prefix, e.g. "Ctrl_". Quotes and underscore are required.<br />
User picks the Excel workbook and clicks OK on LoadData window. Repeat for other conditions. Igor will do the rest!

It will calculate and display the following:
* Cumulative distance over time
* Instantaneous velocity over time, histogram of velocities
* Tracks of all cells for visualisation
* Directionality ratio (d/D) over time
* Mean squared displacement
* Direction autocorrelation.

Reports are made for each condition and also a summary layout comparing all conditions.

### Excel formatting

NOTE: no headers in Excel file. Keep data to columns A-H, max of 1000 rows.

* A - 0 - ImageJ row
* B - 1 - Track No
* C - 2 - Slice No
* D - 3 - x (in px)
* E - 4 - y (in px)
* F - 5 - distance
* G - 6 - velocity
* H - 7 - pixel value

### Colour palettes
Colours are taken from Paul Tol SRON stylesheet. Maximum of 12 conditions are handled.

### Compatability
Written for IgorPro 7 with back-compatability for IgorPro 6.37.

### Notes
\*  Suggestion: each sheet is a field of view, containing all cells in the field. So for two experimental conditions with 10 multipoints each, you will have two workbooks each with 10 worksheets.
