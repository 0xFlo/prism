# LLM Extraction

Harness the power of natural language processing to seamlessly extract data from any website. Our advanced models simplify the extraction process by handling technical complexities such as chunking large documents, tokenization, and other NLP tasks. This allows you to focus on what truly matters while we take care of the heavy lifting.

Minimal API call is a `POST` request with `key` and `extraction_prompt` parameters:

```
https://api.scrapfly.io/extraction?key=&extraction_prompt=
```

#### Benefits

- Ease of Use: No need to worry about technical details; our models manage everything for you.
- Versatile Content Types: Supports various text content types including `text, html, xml, markdown, json, rss, xml, csv`. We plan to support additional content types like `application/pdf` in the future.

## Usage

1. **Retrieve your content:** When using extraction API, you already have the content. For the example we will use the result data structure of the extracted data example from the prompt on the url and save it's content to the current directory where you will run the curl command below as `product.html` ```
   curl https://web-scraping.dev/product/1 > product.html
   ```

   ```
2. **Prepare your prompt:** ```
   Extract the product specification in json format
   ```

   ```
3. **Call the extraction API:** with the your prompt [urlencoded ](https://scrapfly.io/web-scraping-tools/urlencode) `extraction_prompt=Extract%20the%20product%20specification%20in%20json%20format` ```
   curl -X POST \
   -H "content-type: text/html" \
   "https://api.scrapfly.io/extraction?key=scp-live-91655fa2b2a046f5a075fdc25243ad23&url=https%3A%2F%2Fweb-scraping.dev&extraction_prompt=Extract%20the%20product%20specification%20in%20json%20format" \
   -d @product.html

   ```









     Command Explanation
   - **`curl -X POST`**:
       - `curl` is a command-line tool for transferring data with URLs.
       - `-X POST` specifies the HTTP method to be used, which is POST in this case.
   - **`-H "content-type: text/html"`**:
       - `-H` is used to specify an HTTP header for the request.
       - `"content-type: text/html"` sets the Content-Type header to `text/html`, indicating that the data being sent is HTML.
   - **URL**:
       - The URL of the API endpoint being accessed, including query parameters for authentication and specifying the target URL and extraction prompt.
       - [ `key`: ](https://scrapfly.io/docs/extraction-api/getting-started#api_param_key) An API key for authentication.
       - [ `url`: ](https://scrapfly.io/docs/extraction-api/getting-started#api_param_url) The URL of the web page to be scraped, [URL-Encoded ](https://scrapfly.io/web-scraping-tools/urlencode).
       - [ `extraction_prompt`: ](https://scrapfly.io/docs/extraction-api/getting-started#api_param_extraction_prompt) A prompt specifying what to extract, in this case, "Retrieve the latest reviews in a JSON format".
   - **`-d @product.html`**:
       - `-d` is used to specify the data to be sent in the POST request body.
       - `@product.html` indicates that the data should be read from a file named `product.html`.
   ```

4. The result ```
   {
   "content_type": "application/json",
   "data": {
   "description": "Indulge your sweet tooth with our Box of Chocolate Candy. Each box contains an assortment of rich, flavorful chocolates with a smooth, creamy filling. Choose from a variety of flavors including zesty orange and sweet cherry. Whether you're looking for the perfect gift or just want to treat yourself, our Box of Chocolate Candy is sure to satisfy.",
   "features": {
   "brand": "ChocoDelight",
   "care instructions": "Store in a cool, dry place",
   "flavors": "Available in Orange and Cherry flavors",
   "material": "Premium quality chocolate",
   "purpose": "Ideal for gifting or self-indulgence",
   "sizes": "Available in small, medium, and large boxes"
   },
   "packs": [
   {
   "deliveryType": "1 Day shipping",
   "packageDimension": "100x230 cm",
   "packageWeight": "1,00 kg",
   "variants": "6 available",
   "version": "Pack 1"
   },
   {
   "deliveryType": "1 Day shipping",
   "packageDimension": "200x460 cm",
   "packageWeight": "2,11 kg",
   "variants": "6 available",
   "version": "Pack 2"
   },
   {
   "deliveryType": "1 Day shipping",
   "packageDimension": "300x690 cm",
   "packageWeight": "3,22 kg",
   "variants": "6 available",
   "version": "Pack 3"
   },
   {
   "deliveryType": "1 Day shipping",
   "packageDimension": "400x920 cm",
   "packageWeight": "4,33 kg",
   "variants": "6 available",
   "version": "Pack 4"
   },
   {
   "deliveryType": "1 Day shipping",
   "packageDimension": "500x1150 cm",
   "packageWeight": "5,44 kg",
   "variants": "6 available",
   "version": "Pack 5"
   }
   ],
   "price": "9.99 from 12.99",
   "variants": [
   "orange, small",
   "orange, medium",
   "orange, large",
   "cherry, small",
   "cherry, medium",
   "cherry, large"
   ]
   }
   }

   ```









     *You can change the returned data format using the `content_type` parameter.

    When the content type is set to `application/json` scrapfly returns a json object without re-encoding it (json text in json object) for simplicity of usage.*
   ```

> If you are receiving the error [ERR::EXTRACTION::DATA_ERROR](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::DATA_ERROR) make sure to read the description provided with the error code, when the LLM is not able to extract the data you are asking for, it explains the reason why. - The data you are asking for is not present in the document
>
> - Be more precise by adding `In this document,`
> - Use correct semantic related to data extraction, for example replace `retrieve` by `extract`

## Web Scraping API

In this example we will extract the data with the following LLM prompt:

```
Present me the product like you are a sales person, summarize it and give the top pro and cons from reviews in bullet point list
```

> Combined with cache feature, we cache the raw data from the website, allowing you to **re-extract the data with multiple extraction passes** at a **much faster speed** and **lower cost**. This applies to the following extraction types: - [Extraction Template](https://scrapfly.io/docs/extraction-api/rules-and-template)
>
> - [Extraction Model](https://scrapfly.io/docs/extraction-api/automatic-ai)
> - [LLM Extraction](https://scrapfly.io/docs/extraction-api/llm-prompt)
>
>   ##### Learn more about cache feature
>
> - [Cache feature](https://scrapfly.io/docs/scrape-api/cache)
> - [API Specification](https://scrapfly.io/docs/scrape-api/getting-started)

[Curl](#player-1ebc23) [HTTP](#http-1ebc23)

[ Try ](https://scrapfly.io/dashboard/player?config=3gApo3VybNkiaHR0cHM6Ly93ZWItc2NyYXBpbmcuZGV2L3Byb2R1Y3QvMadoZWFkZXJzkKdzZXNzaW9uwLRzZXNzaW9uX3N0aWNreV9wcm94ecOlY2FjaGXDqWNhY2hlX3R0bM4AAVGAq2NhY2hlX2NsZWFywqlyZW5kZXJfanPDpXJldHJ5w6ZtZXRob2SjR0VUo2FzcMOodGhyb3R0bGXCpm9yaWdpbqJVSax3ZWJob29rX25hbWXApGJvZHmgo3NzbMKjZG5zwqdjb3VudHJ5wLF3YWl0X2Zvcl9zZWxlY3RvcsClZGVidWfCq2pzX3NjZW5hcmlvwK5jb3JyZWxhdGlvbl9pZMCkdGFnc5KmcGxheWVyr3Byb2plY3Q6ZGVmYXVsdK1zY2hlZHVsZV9uYW1lwKJqc8CucmVuZGVyaW5nX3dhaXTNA-ikYXV0b8Krc2NyZWVuc2hvdHOQqnByb3h5X3Bvb2y2cHVibGljX2RhdGFjZW50ZXJfcG9vbLBiaWxsaW5nX2ZhaXJfdXNlw6Jvc8CkbGFuZ8CrZ2VvbG9jYXRpb27Ap3RpbWVvdXTOAAJJ8KthdXRvX3Njcm9sbMKrY29zdF9idWRnZXTApmZvcm1hdKNyYXewc2NyZWVuc2hvdF9mbGFnc8CzZXh0cmFjdGlvbl90ZW1wbGF0ZcCwZXh0cmFjdGlvbl9tb2RlbMCxZXh0cmFjdGlvbl9wcm9tcHTZgFByZXNlbnQgbWUgdGhlIHByb2R1Y3QgbGlrZSB5b3UgYXJlIGEgc2FsZXMgcGVyc29uLCBzdW1tYXJpemUgaXQgYW5kIGdpdmUgdGhlIHRvcCBwcm8gYW5kIGNvbnMgZnJvbSByZXZpZXdzIGluIGJ1bGxldCBwb2ludCBsaXN0 "Try in API Player")

```
curl -G \
--request "GET" \
--url "https://api.scrapfly.io/scrape" \
--data-urlencode "tags=player,project:default" \
--data-urlencode "extraction_prompt=Present me the product like you are a sales person, summarize it and give the top pro and cons from reviews in bullet point list" \
--data-urlencode "cache=true" \
--data-urlencode "asp=true" \
--data-urlencode "render_js=true" \
--data-urlencode "key=scp-live-91655fa2b2a046f5a075fdc25243ad23" \
--data-urlencode "url=https://web-scraping.dev/product/1"
```

```
https://api.scrapfly.io/scrape?tags=player%252Cproject%253Adefault&extraction_prompt=Present%2520me%2520the%2520product%2520like%2520you%2520are%2520a%2520sales%2520person%252C%2520summarize%2520it%2520and%2520give%2520the%2520top%2520pro%2520and%2520cons%2520from%2520reviews%2520in%2520bullet%2520point%2520list&cache=true&asp=true&render_js=true&key=scp-live-91655fa2b2a046f5a075fdc25243ad23&url=https%253A%252F%252Fweb-scraping.dev%252Fproduct%252F1
```

The full [Web Scraping API](https://scrapfly.io/docs/scrape-api/getting-started) response structure where the extracted data is available in the `result.extracted_data.data` field:

```
{
   "config" : {
       ...
   },
   "context": {
       ...
   },
   "result": {
       ...
       "content": ".... html content ... too long for the example",
       "content_encoding": "utf-8",
       "content_format": "raw",
       "content_type": "text/html; charset=utf-8",
       "duration": 3.7,
       "error": null,
       "extracted_data": {
           "content_type": "text/plain",
           "data": "Indulge your sweet tooth with our Box of Chocolate Candy! This delightful assortment features rich, flavorful chocolates with a smooth, creamy filling. Choose from zesty orange or sweet cherry flavors, and enjoy the perfect gift or treat yourself. \n\n**Pros:**\n\n* Delicious and flavorful chocolates\n* Variety of flavors to choose from\n* High-quality chocolate\n* Perfect for gifting or self-indulgence\n\n**Cons:**\n\n* Can be a bit pricey\n* Some customers may find the flavors too sweet\n"
       },
       "format": "text",
       "reason": "OK",
       "request_headers": [],
       "response_headers": {
           ...
       },
       "status": "DONE",
       "status_code": 200,
       "success": true,
       "url": "https://web-scraping.dev/product/1"
   }
}
```

## 🔥 Popular LLM Integration

Scrapfly is directly integrated with well known tools to simplify the LLM data retrieval

### LlamaIndex

LlamaIndex, formerly known as GPT Index, is a data framework designed to facilitate the connection between large language models (LLMs) and a wide variety of data sources. It provides tools to effectively ingest, index, and query data within these models.

[ Integrate Scrapfly with LlamaIndex ](https://docs.llamaindex.ai/en/stable/examples/data_connectors/WebPageDemo/?h=scrap#using-scrapfly)### Langchain

LangChain is a robust framework designed for developing applications powered by language models. It focuses on enabling the creation of applications that can leverage the capabilities of large language models (LLMs) for a variety of use cases.

[ Integrate Scrapfly with Langchain ](https://python.langchain.com/v0.2/docs/integrations/document_loaders/scrapfly/#scrapfly)## Limitation

- The maximum length of the prompt is 10,000 characters
- It's possible that we are not able to fulfill all request under heavy load >1k req/s, and with the complexity on GPU shortage/quota the scaling is limited. Also we prioritize the request based on the plan, the free plan has the lowest priority. You will get an error code `ERR::EXTRACTION::OUT_OF_CAPACITY` if this happens.
- The maximum prompt execution time is 25 seconds. The biggest factor is the output (response) size, the bigger the output the longer it takes to process. We observe a TPS (Token per second) between 120 and 150, we expect to reach 500 tokens per second by the end of the year.
  - **Web Scraping API**
    - [Checkout timeout documentation](https://scrapfly.io/docs/scrape-api/understand-timeout)
    - [Timeout parameter specification](https://scrapfly.io/docs/scrape-api/getting-started#api_param_timeout)

## Error Handling

All related errors are listed below. You can see full description and example of error response on the [Errors section](https://scrapfly.io/docs/extraction-api/errors).

- [ERR::EXTRACTION::CONFIG_ERROR](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::CONFIG_ERROR "Parameters sent to the API are not valid") - Parameters sent to the API are not valid
- [ERR::EXTRACTION::CONTENT_TYPE_NOT_SUPPORTED](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::CONTENT_TYPE_NOT_SUPPORTED "The content type of the response is not supported for extraction.") - The content type of the response is not supported for extraction.
- [ERR::EXTRACTION::DATA_ERROR](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::DATA_ERROR "Extracted data is invalid or have an issue") - Extracted data is invalid or have an issue
- [ERR::EXTRACTION::INVALID_RULE](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::INVALID_RULE "The extraction rule is invalid") - The extraction rule is invalid
- [ERR::EXTRACTION::INVALID_TEMPLATE](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::INVALID_TEMPLATE "The template used for extraction is invalid") - The template used for extraction is invalid
- [ERR::EXTRACTION::NO_CONTENT](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::NO_CONTENT "Target response is empty") - Target response is empty
- [ERR::EXTRACTION::OPERATION_TIMEOUT](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::OPERATION_TIMEOUT "Extraction Operation Timeout") - Extraction Operation Timeout
- [ERR::EXTRACTION::OUT_OF_CAPACITY](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::OUT_OF_CAPACITY "Not able to extract more data, backend are out of capacity, retry later.") - Not able to extract more data, backend are out of capacity, retry later.
- [ERR::EXTRACTION::TEMPLATE_NOT_FOUND](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::TEMPLATE_NOT_FOUND "The provided template do not exist") - The provided template do not exist
- [ERR::EXTRACTION::TIMEOUT](https://scrapfly.io/docs/extraction-api/error/ERR::EXTRACTION::TIMEOUT "The extraction was tool long (maximum 25s) or do not had enough time to complete") - The extraction was tool long (maximum 25s) or do not had enough time to complete

## Pricing

LLM extraction is billed **5 API Credits**.

For more information about the pricing you can [learn more on the dedicated section](https://scrapfly.io/docs/extraction-api/billing)
