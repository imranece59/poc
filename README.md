**Problem Statement:**

**Input Data**
Given json contains 20K articles (1 object per line)
Each article contains set of attributes with one set value.

**Recommendation Engine Requirements**
Calculate similarity of articles identified by sku based on their attributes values.
The number of matching attributes is the most important metric for defining similarity.
In case of a draw, attributes with name higher in alphabet (a is higher than z) is weighted with heavier weight.

Example 1:
1 {"sku":"sku-1","attributes": {"att-a": "a1", "att-b": "b1", "att-c": "c1"}} is more similar to
2 {"sku":"sku-2","attributes": {"att-a": "a2", "att-b": "b1", "att-c": "c1"}} than to

3. {"sku":"sku-1","attributes": {"att-a": "a1", "att-b": "b1", "att-c": "c2"}} is more similar to


{"sku":"sku-3","attributes": {"att-a": "a1", "att-b": "b3", "att-c": "c3"}}

Example 2:
{"sku":"sku-1","attributes":{"att-a": "a1", "att-b": "b1"}} is more similar to 
{"sku":"sku-2","attributes":{"att-a": "a1", "att-b": "b2"}} than to
{"sku":"sku-3","attributes":{"att-a": "a2", "att-b": "b1"}}

**Recommendation request example**
sku-123  > ENGINE > 10 most similar SKUs based on criteria described above with their corresponding weights.

**Implementation requirements**
Please use Spark with Scala for your solution
You can use any of Spark's APIs and modules like RDDs, Dataframes, SQL, etc. 
You can use sbt to manage Spark libs
The Spark Application/session should be set up to run on local machine

**Design Approach:**

1. Load the home24-test-data-for-spark.json file into dataframe

2. Flatten the rows in the below format
+-------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|skuName|a       |b       |c       |d       |e       |f       |g       |h       |i       |j       |
+-------+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|sku-1  |att-a-7 |att-b-3 |att-c-10|att-d-10|att-e-15|att-f-11|att-g-2 |att-h-7 |att-i-5 |att-j-14|
|sku-2  |att-a-9 |att-b-7 |att-c-12|att-d-4 |att-e-10|att-f-4 |att-g-13|att-h-4 |att-i-1 |att-j-13|
|sku-3  |att-a-10|att-b-6 |att-c-1 |att-d-1 |att-e-13|att-f-12|att-g-9 |att-h-6 |att-i-7 |att-j-4 |
|sku-4  |att-a-9 |att-b-14|att-c-7 |att-d-4 |att-e-8 |att-f-7 |att-g-14|att-h-9 |att-i-13|att-j-3 |
|sku-5  |att-a-8 |att-b-7 |att-c-10|att-d-4 |att-e-11|att-f-4 |att-g-8 |att-h-8 |att-i-7 |att-j-8 |
|sku-6  |att-a-6 |att-b-2 |att-c-13|att-d-6 |att-e-2 |att-f-11|att-g-2 |att-h-11|att-i-1 |att-j-9 |

3. Calculate the match against each column of every other rows. 
 - if col(a) matches then 9 otherwise -1
 - if col(b) matches then 8 otherwise -1
 - if col(c) matches then 7 otherwise -1
 - if col(d) matches then 6 otherwise -1
 - if col(e) matches then 5 otherwise -1
 - if col(f) matches then 4 otherwise -1
 - if col(g) matches then 3 otherwise -1
 - if col(h) matches then 2 otherwise -1
 - if col(i) matches then 1 otherwise -1
 - if col(j) matches then 0 otherwise -1
 
4. Concatenate all the calculated difference values into single one with the trimmed -1 value
5. Calculate the rank against the difference values(point 4)

**Running**

- sbt "runMain demo.common.SkuRecommendation --sku=sku-12312 --num=10"
- --sku - sku value to calculate similar match / --num - number of similar matches to be returned

**Sample Output**


|Most Similar SKU's|
|------------------|
|sku-14894         |
|sku-10634         |
|sku-5240          |
|sku-11148         |
|sku-19493         |
|sku-1328          |
|sku-15418         |
|sku-4694          |
|sku-19692         |
|sku-1265          |
--------------------
**Eclipse Build**

- Git clone to project
- run sbt eclipse from the project folder
- import the project into ScalaIde/IntelliJ


**Notes**
This is a pure Spark/Scala program which run on local mode. 
- Input file is placed under ./src/main/resources/home24-test-data-for-spark.json folder. No need to specify anywhere.


 
 
 
 
 
 


