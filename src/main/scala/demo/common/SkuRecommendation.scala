package demo.common

import java.util.Properties
import scala.collection.JavaConversions._
import org.apache.spark._
import org.apache.spark.sql.SQLContext
import org.apache.spark.sql.SaveMode
import java.util.Date
import java.util.Calendar
import java.util.Iterator;
import org.apache.spark.sql.functions._
import org.apache.spark.sql.functions.regexp_replace
import org.apache.spark.sql.Row
import org.apache.spark.sql.types.DataType
import org.apache.spark.sql.Column
import org.apache.spark.sql.functions.isInstanceOf
import org.apache.spark.sql.types.TimestampType
import org.apache.spark.storage.StorageLevel
import java.text.SimpleDateFormat
import org.apache.spark.sql.DataFrame
import org.apache.spark.sql.hive._
import org.apache.spark.sql.SparkSession
import java.sql.{Timestamp, Date}
import demo.utils.DataframeReadWriteUtils
import org.apache.spark.sql.types.StructType
import org.apache.spark.sql.types.StructField
import org.apache.spark.sql.types._
import demo.constants.Constants
import demo.helper.ProcessDataHelper
import org.apache.log4j.{Level, Logger}

object SkuRecommendation{

  def main(args:Array[String]){
    
          if (args.isEmpty){
             println(Constants.NO_ARGUMENT_MSG)
             System.exit(0);
          }
          val params = args.map(_.split('=')).map{
          case Array(param,value) => (param, value)
          }.toMap
        
          var skuInput : String=""
          var numOfSimilarSku : Integer = 0
          if (params.contains("--sku")){ 
              skuInput = params.get("--sku").get.asInstanceOf[String]}
          else{
               println(Constants.INVALID_KEY)
               System.exit(0);}
          
          if (params.contains("--num")){ 
              numOfSimilarSku = Integer.parseInt(params.get("--num").get.asInstanceOf[String])}
          else{
               println(Constants.INVALID_KEY)
               System.exit(0);}
          
          val sparkSession = SparkSession.builder
                             .appName("OpsAggModule")
                             .master("local[*]")
                             .getOrCreate
         try {                      
          import sparkSession.implicits._
          val sc = sparkSession.sparkContext
          val hiveContext = new org.apache.spark.sql.hive.HiveContext(sc)
          val inputDf = DataframeReadWriteUtils.creatingDataframeFromJson(sparkSession, Constants.INPUT_FILE_PATH)
          DataframeReadWriteUtils.dataframepersist(inputDf)
          val flattenDf = ProcessDataHelper.flattenJsonColumns(inputDf,hiveContext, sparkSession)
          val filteredSku = ProcessDataHelper.lookupOnInputDf(skuInput, flattenDf)
          val calMismatchDf =ProcessDataHelper.calculateMismatchDf(skuInput,filteredSku, flattenDf)
          DataframeReadWriteUtils.dataframeunpersist(inputDf)
          val resultDf = calMismatchDf.select(col("skuName").alias("Most Similar SKU's")).limit(numOfSimilarSku)
          resultDf.show(false)
          sparkSession.stop
      }catch {
           case e: Exception =>
                   val builder = StringBuilder.newBuilder
                   builder.append(e.getMessage)
                   (e.getStackTrace.foreach { x => builder.append(x + "\n")})
                   val err_message = builder.toString()
                   println(err_message)
                   sparkSession.stop()
                  
               }
}}