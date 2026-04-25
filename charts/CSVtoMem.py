import csv
path = ""

with open(path + "full_template_chart.csv", "r") as csvFile:
       with open(path + "chart.mem", "w") as memFile:
            for row in csv.reader(csvFile):
                memFile.write(" ".join(row) + "\n")

