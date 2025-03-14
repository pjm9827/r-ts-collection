---
title: "2q-element-forecast"
author: "Jinmun Park"
date: "11/8/2019"
output: html_document
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE)
library(ggplot2)
library(stringr) #Split words
library(httr)
library(dplyr)
library(tidyverse)
library(fpp)
library(forecast)
library(randomForest)
library(xgboost)
library(data.table)
```


```{r pressure, echo=FALSE}
setwd("C:/Users/JinmunPark/Box Sync/DS&T/1. Box_SPSS_Services/GTS IRM Elements")
raw = read.csv("C:/Users/JinmunPark/Box Sync/DS&T/1. Box_SPSS_Services/GTS IRM Elements/10-7-19 October Actuals GTS IRM.csv", header = TRUE, sep=",")
ref.minor = read.csv("C:/Users/JinmunPark/Box Sync/DS&T/1. Box_SPSS_Services/GTS IRM Elements/5-20-19 GTS IRM Minors to Element Mapping.csv", header = TRUE, sep=",")
ref.geo = read.csv("C:/Users/JinmunPark/Box Sync/DS&T/1. Box_SPSS_Services/GTS IRM Elements/Geography Naming File.csv", header = TRUE, sep=",")

# Merge 1 : MINOR
df.1 = merge(raw, ref.minor, by = "Expense")

df.1$Measurement = as.character(df.1$Measurement)
df.1$Measurement[df.1$Measurement == "GTS Dual-Global Technology Services - Dual Measurement"] = "GTS DUAL"
df.1$Measurement[df.1$Measurement == "Infrastructure Services - Dual Measurement"] = "IS DUAL"
df.1$Measurement[df.1$Measurement == "WS-Technology Support Services"] = "TSS"

# Variables Setting
df.1$Measurement = as.factor(df.1$Measurement)
df.1$Coverage = as.numeric(levels(df.1$Coverage))[df.1$Coverage]

df.1$Year = as.integer(str_extract(df.1$Year, "[0-9]+"))
df.1$Month = match(df.1$Month, month.abb)

df.1 = df.1 %>% #Aggregate : Not counting Expenses
  group_by(Measurement, Year, Month, Market.Geo, Element) %>%
  summarise(Coverage = sum(Coverage))

df.1$Date = as.Date(paste(df.1$Year, "-", df.1$Month, "-", "1", sep = ""))
df.1$Quarter = quarter(df.1$Date)
df.1$Moq = as.integer(ifelse(df.1$Month == "1" | df.1$Month == "4" | df.1$Month == "7" | df.1$Month == "10", "1", 
                  ifelse(df.1$Month == "2" | df.1$Month == "5" | df.1$Month == "8" | df.1$Month == "11", "2", "3")))

# Variable Setting : R treats NA as Null
ref.geo$GEO = as.character(ref.geo$GEO)
ref.geo$GEO[is.na(ref.geo$GEO)] = "N.A."

df.1$Market.Geo = as.character(df.1$Market.Geo)
df.1$Market.Geo[is.na(df.1$Market.Geo)] = "N.A."

# Variable Setting 2 : R treats -0 as Null
df.1$Coverage[is.na(df.1$Coverage)] = 0

## Cancellation of contract in software (-40)
# Region : U.S 
df.1 %>%
  filter(Market.Geo == "U-U.S.") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01") 

df.1$Coverage = ifelse(df.1$Date == "2018-12-01" & df.1$Market.Geo == "U-U.S." & df.1$Element == "Software", df.1$Coverage-40, df.1$Coverage-0)

df.1 %>%
  filter(Market.Geo == "U-U.S.") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01") 

#Region : N.A
df.1 %>%
  filter(Market.Geo == "N.A.") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01")

df.1$Coverage = ifelse(df.1$Date == "2018-12-01" & df.1$Market.Geo == "N.A." & df.1$Element == "Software", df.1$Coverage-40, df.1$Coverage-0)

df.1 %>%
  filter(Market.Geo == "N.A.") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01")

# Region : W.W 
df.1 %>%
  filter(Market.Geo == "Worldwide Total") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01")

df.1$Coverage = ifelse(df.1$Date == "2018-12-01" & df.1$Market.Geo == "Worldwide Total" & df.1$Element == "Software", df.1$Coverage-40, df.1$Coverage-0)

df.1 %>%
  filter(Market.Geo == "Worldwide Total") %>%
  filter(Element == "Software") %>%
  filter(Date == "2018-12-01")

# Merge 2 : GEO
df = merge(df.1, ref.geo, by = "Market.Geo")

# Identifer
df$Identifier = paste(df$File.Naming, "-", df$Measurement, "-", df$Element, sep = "")

```


Model Building 1 : Setting

```{r}
# Sort Maintenenace only
df.aggregate = df %>%
  filter(Element == "Maintenance") %>%
  group_by(Date, Identifier) %>% 
  summarise(Coverage = sum(Coverage))

# Aggregate Column
df.aggregate = dcast(df.aggregate, Date~...)

# Time Series 
ts.aggregate = ts(df.aggregate[,-1], start = c(2017, 1), end = c(2019, 9), frequency = 12)

# ncolumn
ncol = ncol(ts.aggregate)

# Naming
col.name = df.aggregate[,-1]
col.name = colnames(col.name)

# Random Forest Setting
lag_order = 6


# Vlookup
random = c("abc")
accuracy.summary = c("accuracy.1", "accuracy.2", "accuracy.3", "accuracy.4", "accuracy.5", "accuracy.6", "accuracy.7", "accuracy.8")
forecast.model = c("arm.auto.fcst.2$mean","nnt.auto.fcst.2$mean","ets.auto.fcst.2$mean", "rf.fcst.2", "ensemble.all.2", "ensemble.rf.2", "ensemble.ets.2", "ensemble.two.2")

sort = cbind(accuracy.summary, forecast.model)
sort = data.frame(sort)

```


Model Building 2 : Random Forest (Train)

```{r}
# Random Forest Setting
fcst.matrix.rf.1 = matrix(NA, nrow = 3, ncol = ncol)
colnames(fcst.matrix.rf.1) = col.name

# Random Forest Working
for (i in 1:ncol){
  train.rf.1 = window(ts.aggregate[,i], start = c(2017, 1), end = c(2018, 12), frequency = 12) # same as train
  
  test.rf.1 = window(ts.aggregate[,i], start = c(2019, 1), end = c(2019, 3), frequency = 12) # same as test
  
  h.rf.1 = length(test.rf.1)

  embedding.1 = embed(train.rf.1, lag_order + 1) 

  y_train = embedding.1[, 1]

  X_train = embedding.1[, -1] 

  X_test = embedding.1[nrow(embedding.1), c(1:lag_order)] 

  forecasts_rf = numeric(h.rf.1)


  for (j in 1:h.rf.1){
   
    set.seed(2019)

    fit_rf = randomForest(X_train, y_train)

    forecasts_rf[j] = predict(fit_rf, X_test)

    y_train = y_train[-1] 

    X_train = X_train[-nrow(X_train), ] 
    
  }

forecast_rf = matrix(forecasts_rf)

fcst.matrix.rf.1[,i] = forecast_rf

#write.table(fcst.matrix, file = "C:/Users/JinmunPark/Desktop/percentage2.csv", sep=",", append = F, row.names = T, col.names = NA)
}

```


Model Building 3 : Random Forest (Actual)

```{r}
# Random Forest Setting
fcst.matrix.rf.2 = matrix(NA, nrow = 3, ncol = ncol)
colnames(fcst.matrix.rf.2) = col.name

# Random Forest Working
for (i in 1:ncol){
  train.rf.2 = window(ts.aggregate[,i], start = c(2017, 1), end = c(2019, 3), frequency = 12) # same as 'use'
  
  test.rf.2 = window(ts.aggregate[,i], start = c(2019, 4), end = c(2019, 6), frequency = 12) # same as 'actual'
  
  h.rf.2 = length(test.rf.2)

  embedding.2 = embed(train.rf.2, lag_order + 1) 

  y_train = embedding.2[, 1]

  X_train = embedding.2[, -1] 

  X_test = embedding.2[nrow(embedding.2), c(1:lag_order)] 

  forecasts_rf = numeric(h.rf.2)


  for (j in 1:h.rf.2){
   
    set.seed(2019)

    fit_rf = randomForest(X_train, y_train)

    forecasts_rf[j] = predict(fit_rf, X_test)

    y_train = y_train[-1] 

    X_train = X_train[-nrow(X_train), ] 
    
  }

forecast_rf = matrix(forecasts_rf)

fcst.matrix.rf.2[,i] = forecast_rf

#write.table(fcst.matrix, file = "C:/Users/JinmunPark/Desktop/percentage2.csv", sep=",", append = F, row.names = T, col.names = NA)
}

```


Model
```{r}
# Matrix
list.model = matrix(NA, nrow = ncol, ncol = 3)
row.names(list.model) = col.name

# Loop
result = function() {
 for( i in 1:ncol){
  train = window(ts.aggregate[,i], start = c(2017, 1), end = c(2018, 12), frequency = 12) ###
  test = window(ts.aggregate[,i], start = c(2019, 1), end = c(2019, 3), frequency = 12) ###
  h1 = length(test)

  use = window(ts.aggregate[,i], start = c(2017, 1), end = c(2019, 3), frequency = 12) #Train begin ~ Test end ###
  actual = window(ts.aggregate[,i], start = c(2019, 4), end = c(2019, 6), frequency = 12) ###
  h2 = length(actual)

  # Model : Test
  arm.auto.1 = auto.arima(train)
  arm.auto.fcst.1 = forecast(arm.auto.1, h=h1) #1

  nnt.auto.1 = nnetar(train, repeats = 500)
  nnt.auto.fcst.1 = forecast(nnt.auto.1, h = h1, PI = F) #2
  
  ets.auto.1 = ets(train)
  ets.auto.fcst.1 = forecast(ets.auto.1, h = h1) #3
  
  rf.fcst.1 = ts(fcst.matrix.rf.1[,i], start = c(2019, 1), end = c(2019, 3), frequency = 12) #Same as "Train Period" #4 ###
  
  ensemble.all.1 = (arm.auto.fcst.1$mean + nnt.auto.fcst.1$mean + ets.auto.fcst.1$mean + rf.fcst.1)/4 #5
  ensemble.rf.1 = (arm.auto.fcst.1$mean + nnt.auto.fcst.1$mean + rf.fcst.1)/3 #6
  ensemble.ets.1 = (arm.auto.fcst.1$mean + nnt.auto.fcst.1$mean + ets.auto.fcst.1$mean)/3 #7
  ensemble.two.1 = (arm.auto.fcst.1$mean + nnt.auto.fcst.1$mean)/2 #8
  
  # Accuracy
  accuracy.1 = accuracy(test, arm.auto.fcst.1$mean)[,3]
  accuracy.2 = accuracy(test, nnt.auto.fcst.1$mean)[,3]
  accuracy.3 = accuracy(test, ets.auto.fcst.1$mean)[,3]
  accuracy.4 = accuracy(test, rf.fcst.1)[,3]
  accuracy.5 = accuracy(test, ensemble.all.1)[,3]
  accuracy.6 = accuracy(test, ensemble.rf.1)[,3]
  accuracy.7 = accuracy(test, ensemble.ets.1)[,3]
  accuracy.8 = accuracy(test, ensemble.two.1)[,3]
  
  # Select best accuracy
  accr.summary = cbind(accuracy.1, accuracy.2, accuracy.3, accuracy.4, accuracy.5, accuracy.6, accuracy.7, accuracy.8) 
  select = colnames(accr.summary)[apply(accr.summary, 1, which.min)]
  select = cbind(select, random)
  colnames(select) = c("accuracy.summary", "forecast.model")
  select = data.frame(select)
  
  best = merge(select, sort, by = "accuracy.summary")
  best.word = as.character(best[1,3]) 
  
  # Model : Actual 
  arm.auto.2 = auto.arima(use)
  arm.auto.fcst.2 = forecast(arm.auto.2, h=h2)
  
  nnt.auto.2 = nnetar(use, repeats = 500)
  nnt.auto.fcst.2 = forecast(nnt.auto.2, h = h2, PI = F)

  ets.auto.2 = ets(use)
  ets.auto.fcst.2 = forecast(ets.auto.2, h = h2)
  
  rf.fcst.2 = ts(fcst.matrix.rf.2[,i], start = c(2019, 4), end = c(2019, 6), frequency = 12) # same as "Actual Period"

  ensemble.all.2 = (arm.auto.fcst.2$mean + nnt.auto.fcst.2$mean + ets.auto.fcst.2$mean)/3
  ensemble.rf.2 = (arm.auto.fcst.2$mean + nnt.auto.fcst.2$mean + rf.fcst.2)/3 
  ensemble.ets.2 = (arm.auto.fcst.2$mean + nnt.auto.fcst.2$mean + ets.auto.fcst.2$mean)/3 
  ensemble.two.2 = (arm.auto.fcst.2$mean + nnt.auto.fcst.2$mean)/2 
  
  # Select the model
  
  fcst.summary = cbind(arm.auto.fcst.2$mean, nnt.auto.fcst.2$mean, ets.auto.fcst.2$mean, rf.fcst.2, ensemble.all.2, ensemble.rf.2, ensemble.ets.2, ensemble.two.2) 
  fcst.select = fcst.summary[, grepl(best.word, colnames(fcst.summary), fixed = T)]

  # Table : Actual vs Forecast
  product = fcst.select
  #product = cbind(actual, fcst.select)
  product.rownames = col.name[i]
  #product.colnames = paste(col.name[i], colnames(product)) 
  #colnames(product) = product.colnames
  product = t(product)
 
  list.model[i,] = product
    
  # write.table(product, file = "C:/Users/JinmunPark/Desktop/RF_Included IRM Element.csv", sep=",", append = T, row.names = T, col.names = F)
  }
  return(list.model)
}

# Replicate 5 Times
result.rep = replicate(5, result())

# Actual 
act = window(ts.aggregate, start = c(2019, 4), end = c(2019, 6), frequency = 12)
act.rownames = paste(colnames(act), "-", "actual", sep = "") 
act = t(act)
row.names(act) = act.rownames

# Average the replicate and rename
result.rep.avg = (result.rep[, , 1] + result.rep[, , 2] + result.rep[, , 3] + result.rep[, , 4] + result.rep[, , 5])/5

rep.rownames = paste(rownames(result.rep.avg), "-", "fcst", sep = "") 
row.names(result.rep.avg) = rep.rownames

# Combine
final.result = rbind(act, result.rep.avg)
final.result = final.result[order(row.names(final.result)),]

# Export
write.table(final.result, file = "C:/Users/JinmunPark/Desktop/IRM Element final output_RF added.csv", sep=",", append = T, row.names = T, col.names = F)  

 
```

Note that the `echo = FALSE` parameter was added to the code chunk to prevent printing of the R code that generated the plot.
