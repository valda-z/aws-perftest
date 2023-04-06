using Microsoft.AspNetCore.Mvc;

namespace PerfTest.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class TestController : ControllerBase
    {

        private readonly ILogger<TestController> _logger;

        public TestController(ILogger<TestController> logger)
        {
            _logger = logger;
        }

        [HttpGet]
        public async Task<ObjectResult> Get()
        {
            int randomNumber = GenerateRandomNumber();
            await Task.Delay(randomNumber);

            return Ok("{\"status\":\"ok\"}");
        }

        public static int GenerateRandomNumber()
        {
            Random random = new Random();
            int lowerBound = 200;
            int upperBound = 3000;
            int median = 550;

            int randomNumber;
            if (random.Next(2) == 0)
            {
                // Generate a number between lowerBound and median
                randomNumber = random.Next(lowerBound, median + 1);
            }
            else
            {
                // Generate a number between median and upperBound
                randomNumber = random.Next(median, upperBound + 1);
            }

            return randomNumber;
        }
    }
}