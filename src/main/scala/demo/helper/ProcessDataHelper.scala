package demo.helper

import org.apache.spark.sql.DataFrame
import org.apache.spark.sql.Row
import org.apache.spark.rdd.RDD
import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.hive.HiveContext
import demo.model.SkuDetails
import org.apache.spark.sql.functions._
import org.apache.spark.sql.functions.regexp_replace
import org.apache.spark.sql.types.IntegerType
import org.apache.spark.sql.types.StringType
import demo.constants.Constants
import org.apache.spark.sql.expressions.Window
object ProcessDataHelper {
  
        /**
       	*  Process the Rdd
       	*/
        def flattenJsonColumns(df : DataFrame, hiveContext : HiveContext, sparkSession : SparkSession):DataFrame = {
              val  flattenRDD = df.rdd.map(x =>
                          SkuDetails(x.getAs("sku").asInstanceOf[String], x.getAs("attributes").asInstanceOf[Row].get(0).asInstanceOf[String],
                              x.getAs("attributes").asInstanceOf[Row].get(1).asInstanceOf[String], x.getAs("attributes").asInstanceOf[Row].get(2).asInstanceOf[String],
                              x.getAs("attributes").asInstanceOf[Row].get(3).asInstanceOf[String], x.getAs("attributes").asInstanceOf[Row].get(4).asInstanceOf[String],
                              x.getAs("attributes").asInstanceOf[Row].get(5).asInstanceOf[String], x.getAs("attributes").asInstanceOf[Row].get(6).asInstanceOf[String],
                              x.getAs("attributes").asInstanceOf[Row].get(7).asInstanceOf[String], x.getAs("attributes").asInstanceOf[Row].get(8).asInstanceOf[String],
                              x.getAs("attributes").asInstanceOf[Row].get(9).asInstanceOf[String]
                          ))
              import sparkSession.implicits._            
              val flattenDf = flattenRDD.toDF()
              flattenDf
        }
        
        /**
       	*  Lookup on the Dataframe
       	*/
        def lookupOnInputDf(skuName : String, df : DataFrame): SkuDetails = {
            
            val filteredDf = df.filter(s"skuName =='$skuName'")
            if (filteredDf.rdd.isEmpty()){
                println(Constants.SKU_NOT_FOUND)
                System.exit(0)
            }
            val  flattenRDD = filteredDf.rdd.map(x =>
                        SkuDetails(x.getAs("skuName").asInstanceOf[String], x.getAs("a").asInstanceOf[String],
                        x.getAs("b").asInstanceOf[String],x.getAs("c").asInstanceOf[String],x.getAs("d").asInstanceOf[String],
                        x.getAs("e").asInstanceOf[String],x.getAs("f").asInstanceOf[String],x.getAs("g").asInstanceOf[String],
                        x.getAs("h").asInstanceOf[String], x.getAs("i").asInstanceOf[String], x.getAs("j").asInstanceOf[String]
                        ))
            flattenRDD.collect.apply(0)
        }
        
        /**
       	*  calculate mismatch with other sku's
       	*/
        def calculateMismatchDf(skuName : String ,skuDetails : SkuDetails, df : DataFrame): DataFrame = {
          
          val a = skuDetails.a
          val b = skuDetails.b
          val c = skuDetails.c
          val d = skuDetails.d
          val e = skuDetails.e
          val f = skuDetails.f
          val g = skuDetails.g
          val h = skuDetails.h
          val i = skuDetails.i
          val j = skuDetails.j
          
          df.filter(s"skuName !='$skuName'")
            .withColumn("col_a_diff",  when(col("a") === s"$a",9).otherwise(-1))
            .withColumn("col_b_diff",  when(col("b") === s"$b",8).otherwise(-1))
            .withColumn("col_c_diff",  when(col("c") === s"$c",7).otherwise(-1))
            .withColumn("col_d_diff",  when(col("d") === s"$d",6).otherwise(-1))
            .withColumn("col_e_diff",  when(col("e") === s"$e",5).otherwise(-1))
            .withColumn("col_f_diff",  when(col("f") === s"$f",4).otherwise(-1))
            .withColumn("col_g_diff",  when(col("g") === s"$g",3).otherwise(-1))
            .withColumn("col_h_diff",  when(col("h") === s"$h",2).otherwise(-1))
            .withColumn("col_i_diff",  when(col("i") === s"$i",1).otherwise(-1))
            .withColumn("col_j_diff",  when(col("j") === s"$j",0).otherwise(-1))
            .withColumn("concatealldiffcols",  regexp_replace(concat(col("col_a_diff"),col("col_b_diff"),col("col_c_diff"),col("col_d_diff"),
                                           col("col_e_diff"),col("col_f_diff"),col("col_g_diff"),col("col_h_diff"),col("col_i_diff"),
                                           col("col_j_diff")).cast(StringType),"-1","").cast(IntegerType))
            .withColumn("rank",  rank.over(Window.orderBy("concatealldiffcols")))
            .orderBy(col("rank").desc)
        }
}